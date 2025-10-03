# SIEM
Als SIEM Lösung wurde Wazuh ausgewählt. Wazuh ist Open Source und daher kostenfrei nutzbar. Es bietet die Möglichkeit auf Basis von Regeln Sicherheitsereignisse zu erkennen, zentral zu sammeln und Administratoren zu benachrichtigen. Zudem stehen Active-Response-Möglichkeiten zur Verfügung, mit denen direkt auf die Ereignisse reagiert werden kann. Außerdem bietet Wazuh die Möglichkeit Compliance zu prüfen. Der Wazuh-Agent sollte dabei auf sämtlichen Systemen installiert sein um dort Daten zu sammeln und an den zentralen Wazuh-Server weiterzuleiten.

<br>

# Reverse Proxy
Als Reverse Proxy wurde Nginx gewählt. Nginx bietet im Vergleich zu Apache eine bessere Performance. Da zudem keine spezialisierte Verarbeitung von HTTP-Verkehr stattfinden soll, ist der Funktionsumfang von Nginx ausreichend. Kompatibilität mit der gewählten WAF ist vorhanden.

<br>

# WAF
Für die WAF wurde Modsecurity in Kombination mit dem OWASP Core Rule Set (CRS) gewählt. Diese sollten auf einem Nginx Reverse Proxy laufen. Auch diese Technologien sind Open Source und bieten die Möglichkeit zu einer kostenfreien Nutzung. Über Nginx kann dabei TLS terminiert werden was eine analyse des Netzwerkverkehrs durch Modsecurity ermöglicht.

<br>

