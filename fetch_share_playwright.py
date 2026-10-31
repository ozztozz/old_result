import asyncio
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        print("Navigating to share URL...")
        await page.goto("https://share.gemini.google/HatpsaliEnNz", wait_until="networkidle", timeout=60000)
        print("Page loaded, waiting 5 seconds for rendering...")
        await page.wait_for_timeout(5000)

        # Take a screenshot to be sure
        await page.screenshot(path="playwright_share.png", full_page=True)

        content = await page.content()
        with open("playwright_page.html", "w", encoding="utf-8") as f:
            f.write(content)

        # Extract text from message elements
        text = await page.evaluate("""() => {
            const results = [];
            // Select all possible message containers
            const elements = document.querySelectorAll('.user-query, .response-container, message-content, [data-test-id], .model-response-text, p, h1, h2, h3, li, pre');
            for (const el of elements) {
                const t = el.innerText.trim();
                if (t.length > 10) {
                    results.push(t);
                }
            }
            return results;
        }""")

        with open("playwright_extracted.txt", "w", encoding="utf-8") as f:
            for item in set(text):
                f.write(item + "\n" + "="*50 + "\n")

        # Also get all body innerText
        body_text = await page.inner_text("body")
        with open("playwright_body_text.txt", "w", encoding="utf-8") as f:
            f.write(body_text)

        print("Extracted body text length:", len(body_text))
        await browser.close()

if __name__ == "__main__":
    asyncio.run(main())

