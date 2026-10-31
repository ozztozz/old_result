import subprocess

chrome_path = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
url = "https://gemini.google.com/share/31039f0c9189"

print("Running headless chrome...")
res = subprocess.run([
    chrome_path,
    "--headless=new",
    "--dump-dom",
    "--virtual-time-budget=10000",
    "--no-sandbox",
    "--disable-gpu",
    url
], capture_output=True)

print("Return code:", res.returncode)
print("Stdout len:", len(res.stdout))
print("Stderr len:", len(res.stderr))

with open("chrome_dump.html", "wb") as f:
    f.write(res.stdout)

print("Saved to chrome_dump.html")

