
import glob, re
from collections import Counter
from pathlib import Path

files = sorted(glob.glob('output/txt/ankara/*.txt'))

# We want to see all unclassified lines
# Let us run test logic
