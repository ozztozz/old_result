from bs4 import BeautifulSoup
import re

with open("chrome_dump.html", "r", encoding="utf-8") as f:
    html = f.read()

soup = BeautifulSoup(html, "html.parser")

with open("parsed_gemini_chat.txt", "w", encoding="utf-8") as out:
    # Find user queries and model responses
    # In Gemini web: user queries are usually in .user-query or [data-test-id="user-query"] or message-content
    # Let's find all text blocks with class or role
    for el in soup.find_all(True):
        classes = el.get("class", [])
        if any("query" in c or "message" in c or "response" in c or "content" in c or "markdown" in c for c in classes):
            text = el.get_text().strip()
            if len(text) > 30:
                # check if not already written parent
                out.write(f"[{el.name} class={classes}]\n")
                out.write(text + "\n" + "="*50 + "\n")

    # If that didn't catch, dump all headings, paragraphs, code blocks
    out.write("\n\n>>> ALL PARAGRAPHS & HEADINGS & CODE <<<\n\n")
    for tag in soup.find_all(['h1', 'h2', 'h3', 'p', 'pre', 'ul', 'ol']):
        t = tag.get_text().strip()
        if len(t) > 20:
            out.write(f"<{tag.name}>\n{t}\n\n")

print("Parsed successfully.")

