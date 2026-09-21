"""Read-only audit of the owner's CSV. Buyer-level outputs stay in ignored _local."""
import csv, hashlib, json
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path

root = Path(__file__).resolve().parents[2]
private = root / '_local/trello-20260915'
source = private / 'sales.csv'
rows = list(csv.DictReader(source.open(encoding='utf-8-sig', newline='')))
ids = Counter(r['Id'] for r in rows)
groups = defaultdict(lambda: {'rows': 0, 'price': Decimal(0), 'revenue': Decimal(0)})
buyers = defaultdict(lambda: {'price': Decimal(0), 'transactions': []})
anomalies = []
for n, r in enumerate(rows, 2):
    price, revenue = Decimal(r['Price']), Decimal(r['Revenue'])
    k = (r['Universe Id'], r['Asset Type'], r['Status'])
    g = groups[k]
    g['rows'] += 1
    g['price'] += price
    g['revenue'] += revenue
    if price < 0 or price != price.to_integral_value():
        anomalies.append({'row': n, 'reason': 'negative/fractional price', 'price': str(price)})
    if not r['Buyer User Id'].isdigit():
        anomalies.append({'row': n, 'reason': 'invalid buyer id'})
    buyer = buyers[r['Buyer User Id']]
    buyer['price'] += price
    buyer['transactions'].append(r)

summary = {
    'source': source.name,
    'sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'rows': len(rows), 'unique_ids': len(ids), 'duplicate_ids': [k for k,v in ids.items() if v > 1],
    'buyers': len(buyers),
    'first_transaction': min(r['Date and Time'] for r in rows),
    'last_transaction': max(r['Date and Time'] for r in rows),
    'gross_price': str(sum((Decimal(r['Price']) for r in rows), Decimal(0))),
    'net_revenue': str(sum((Decimal(r['Revenue']) for r in rows), Decimal(0))),
    'groups': [dict(zip(('universe', 'asset_type', 'status'),k), **v) for k,v in groups.items()],
    'anomalies': anomalies,
    'id_lengths': dict(Counter(len(r['Id']) for r in rows)),
    'by_asset': [dict(asset_id=k[0],name=k[1],rows=len(v),price=str(sum((Decimal(r['Price']) for r in v),Decimal(0)))) for k,v in sorted((k,[r for r in rows if (r['Asset Id'],r['Asset Name'])==k]) for k in set((r['Asset Id'],r['Asset Name']) for r in rows))],
}
(private / 'sales-audit.json').write_text(json.dumps(summary, indent=2, default=str), encoding='utf-8')
(private / 'sales-by-buyer.json').write_text(json.dumps(buyers, indent=2, default=str), encoding='utf-8')
print(json.dumps(summary, indent=2, default=str))
