// Read-only parser for Roblox Script Profiler v2 JSON (raw or {Data: json}).
// Usage: node analyze-script-profile.mjs /absolute/path/to/profile.json
// Durations are microseconds; timestamps are milliseconds. No frame percentiles.
import fs from 'node:fs';
import crypto from 'node:crypto';

const input = process.argv[2];
if (!input) throw new Error('A profile JSON path is required');
const bytes = fs.readFileSync(input);
const wrapper = JSON.parse(bytes.toString('utf8'));
const profile = typeof wrapper.Data === 'string' ? JSON.parse(wrapper.Data) : wrapper;
if (profile.Version !== 2) throw new Error('Only inspected profiler schema v2 is supported');
const nodes = profile.Nodes, functions = profile.Functions;
const seen = new Set(), roots = [], poolEntries = [], refreshEntries = [];
let minimumSelfDuration = Infinity;
const isPool = f => /^ServerScriptService\.Level 2 Systems\.Level 2 Pool Slide (Controller|Navigator|Rig Adapter)$/.test(f.Source ?? '');

function visit(id, category, ancestors, poolAncestor = false) {
  if (!Number.isInteger(id) || id < 1 || id > nodes.length) throw new Error('Invalid node id');
  if (seen.has(id)) throw new Error('Shared/cyclic node graph: deduplication needs review');
  seen.add(id);
  const node = nodes[id - 1];
  const ids = node.NodeIds ?? [], funcs = node.FunctionIds ?? [];
  if (ids.length !== funcs.length) throw new Error('Misaligned child/function arrays');
  let childTotal = 0;
  for (let i = 0; i < ids.length; i++) {
    const fn = functions[funcs[i] - 1];
    if (!fn || !nodes[ids[i] - 1]) throw new Error('Invalid function/child reference');
    const duration = nodes[ids[i] - 1].TotalDuration;
    childTotal += duration;
    const pool = isPool(fn);
    const row = {Category: category, NodeId: ids[i], FunctionId: funcs[i],
      Source: fn.Source ?? null, Name: fn.Name ?? '<anonymous>', Line: fn.Line ?? null,
      InclusiveMicroseconds: duration,
      Ancestors: ancestors.map(a => a.Source ? `${a.Source}:${a.Line ?? '?'}:${a.Name ?? '<anonymous>'}` : a.Name ?? '<anonymous>')};
    // First matching function on each callgraph branch owns the whole subtree.
    // Descendant Pool Slide functions are not added again to the entity total.
    if (pool && !poolAncestor) poolEntries.push(row);
    if (pool && fn.Name === '_refreshObstacleFilters') refreshEntries.push(row);
    visit(ids[i], category, [...ancestors, fn], poolAncestor || pool);
  }
  minimumSelfDuration = Math.min(minimumSelfDuration, node.TotalDuration - childTotal);
}

for (const category of profile.Categories) {
  roots.push({Category: category.Name, NodeId: category.NodeId,
    InclusiveMicroseconds: nodes[category.NodeId - 1].TotalDuration});
  visit(category.NodeId, category.Name, []);
}
const sum = a => a.reduce((n, x) => n + x.InclusiveMicroseconds, 0);
const total = sum(roots), pool = sum(poolEntries), refresh = sum(refreshEntries);
const diagnosticPool = sum(poolEntries.filter(row => row.Ancestors.some(a => /TEMP_Pump3NativeServer|AssistantCommand/.test(a))));
const elapsedMs = profile.SessionEndTime - profile.SessionStartTime;
const refreshFunction = functions.filter(f => isPool(f) && f.Name === '_refreshObstacleFilters');
if (refreshFunction.length !== 1 || refresh !== refreshFunction[0].TotalDuration)
  throw new Error('Refresh callgraph/function totals disagree; review recursion/attribution');
if (seen.size !== nodes.length || minimumSelfDuration < 0)
  throw new Error('Unreachable nodes or invalid inclusive duration partition');
console.log(JSON.stringify({
  ProfileSha256: crypto.createHash('sha256').update(bytes).digest('hex'),
  SchemaVersion: profile.Version, Nodes: nodes.length, Functions: functions.length,
  Source: 'https://create.roblox.com/docs/studio/optimization/scriptprofiler',
  SessionStartUTC: new Date(profile.SessionStartTime).toISOString(),
  SessionEndUTC: new Date(profile.SessionEndTime).toISOString(),
  SessionElapsedSeconds: elapsedMs / 1000,
  TotalSampledScriptMicroseconds: total,
  PoolSlideUniqueInclusiveMicroseconds: pool,
  PoolSlideDiagnosticCallerInclusiveMicroseconds: diagnosticPool,
  PoolSlideNonDiagnosticCallerInclusiveMicroseconds: pool - diagnosticPool,
  PoolSlideShareOfSampledScriptPercent: pool / total * 100,
  PoolSlideSampledMillisecondsPerWallSecond: pool / elapsedMs,
  RefreshObstacleFiltersInclusiveMicroseconds: refresh,
  RefreshShareOfPoolSlideInclusivePercent: refresh / pool * 100,
  RefreshShareOfSampledScriptPercent: refresh / total * 100,
  FrameMedianMilliseconds: null, FrameP95Milliseconds: null,
  Limitations: 'Aggregate sampled script CPU only, including native calls attributed to script stacks; not total hardware CPU, frame percentiles, physics/rendering cost, or memory/leak certification. Nested inclusive functions are not summed for entity attribution.',
  CategoryRoots: roots, PoolSlideFirstEntryNodes: poolEntries,
  RefreshObstacleFilterCallgraphNodes: refreshEntries,
}, null, 2));
