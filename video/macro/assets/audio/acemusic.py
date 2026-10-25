#!/usr/bin/env python3
"""Pide un tema instrumental a ACE Music. Uso: ACE_MUSIC_API_KEY=... acemusic.py <nombre> "<prompt>" <segundos>"""
import base64, json, os, sys, urllib.request

name, prompt, dur = sys.argv[1], sys.argv[2], int(sys.argv[3])
body = {"model": "acemusic/acestep-v1.5-turbo", "messages": [{"role": "user", "content": f"<prompt>{prompt}</prompt>"}],
        "use_cot_caption": False, "audio_config": {"instrumental": True, "duration": dur, "format": "mp3"}}
# Sin User-Agent la API devuelve 403.
req = urllib.request.Request("https://api.acemusic.ai/v1/chat/completions", data=json.dumps(body).encode(),
                             headers={"User-Agent": "curl/8.0", "Content-Type": "application/json",
                                      "Authorization": "Bearer " + os.environ["ACE_MUSIC_API_KEY"]})
msg = json.load(urllib.request.urlopen(req, timeout=170))["choices"][0]["message"]
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), name + ".mp3")
open(out, "wb").write(base64.b64decode(msg["audio"][0]["audio_url"]["url"].split(",", 1)[1]))
print(out)
