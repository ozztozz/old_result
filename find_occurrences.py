with open('gemini_share.html', 'r', encoding='utf-8') as f:
    html = f.read()

target = '31039f0c9189'
idx = 0
with open('occurrences.txt', 'w', encoding='utf-8') as out:
    while True:
        pos = html.find(target, idx)
        if pos == -1:
            break
        start = max(0, pos - 500)
        end = min(len(html), pos + 1500)
        out.write(f"=== Occurrence at {pos} ===\n")
        out.write(html[start:end] + "\n\n")
        idx = pos + len(target)

print("Occurrences dumped.")

