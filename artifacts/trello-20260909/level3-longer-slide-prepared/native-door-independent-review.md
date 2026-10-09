# Independent door fixture review — 9/10

Read the complete fixture, actual World Builder sensor frame and Objective.DebugOpenExit/openPressureDoors implementation; independently compiled the whole file. SHA-256 `e05c59e0c185a82cc6e768672d64f59962dc5c8165169e290555f6e172ccc08c`. No necessary correction found.

The actual completion beam's CFrame X/RightVector is authored from the downhill sensor axis, so the 18-stud upstream staging point and initial 40-stud/s momentum point through the intended sensor. The current HRP-to-model correction preserves exact root placement despite PivotOffset. Actual player/character/health/round/place guards precede the setup; the production door method enables sensors after staging and also makes Foam lethal. No escape/transition/ready flag, touch signal, ack or result remote is forged. Normal physics and campaign/result logic must provide the later evidence.

This is a mutating setup fixture: one real character is repositioned, initial momentum is assigned, and the existing controlled objective API opens the exit. The 15-second status print is only a readback, not an acceptance assertion. Run as an ordinary server Script in the known production module cache, retain its output and verify actual sensor completion; it deletes only that disposable Script. No fixture execution or gameplay/source/UI mutation was performed by this review.
