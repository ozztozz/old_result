import os
from dotenv import load_dotenv
load_dotenv()
from google import genai

key = os.environ.get('GEMINI_API_KEY', '').strip()
print('Testing key locally...')
try:
    client = genai.Client(api_key=key)
    res = client.models.generate_content(model='gemini-flash-lite-latest', contents='Hello')
    print('Local test succeeded:', res.text)
except Exception as e:
    print('Local test error:', e)

