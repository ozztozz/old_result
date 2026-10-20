import re

kl = "_ as     Marlin Yüzme Spor Kulübü"
m_lead = re.match(
    r"^[_\.,:;~#‘'\"`\(\)=\+\-\*\>\<\|\!\?«»“”\s]*"
    r"(?:\(?#?([a-zA-Z0-9İıçğıöşüÇĞIÖŞÜ]{1,3})\)?\b)?"
    r"[_\.,:;~#‘'\"`\(\)=\+\-\*\>\<\|\!\?«»“”\s]*"
    r"(.*)$",
    kl
)
print("Groups:", m_lead.groups() if m_lead else None)

