UNDERTOW fonts (both SIL Open Font License 1.1)

1. Share Tech Mono Regular  (body text, labels, buttons)
   File:     ShareTechMono-Regular.ttf
   Licence:  OFL-ShareTechMono.txt
   Source:   Google Fonts, https://github.com/google/fonts/tree/main/ofl/sharetechmono
   Added:    2026-10-07 (Phase 1)

2. Oxanium, variable weight axis wght 200..800  (display face: headings, numerals)
   File:     Oxanium[wght].ttf  (43,536 bytes)
   Licence:  OFL-Oxanium.txt  (Copyright 2019 The Oxanium Project Authors)
   Source:   https://github.com/google/fonts/raw/main/ofl/oxanium/Oxanium%5Bwght%5D.ttf
             https://github.com/google/fonts/raw/main/ofl/oxanium/OFL.txt
   Upstream: https://github.com/sevmeyer/oxanium
   Downloaded: 2026-10-10 (Phase 02.2 plan 04, decision D-03)
   SHA-256 (Oxanium[wght].ttf): 2ce01d946e1e1ffc8d7eecfffbda8623bedd63eaf811a20488c4b69af45babb0
   SHA-256 (OFL-Oxanium.txt):   fe17c0f2581d71b4e1ea7e636e7f4877c29223e11bb1dd1a871e8c3f2a86336b

   Weight 700 is set in code (Palette.display_font) with the INTEGER OpenType tag
   TextServerManager.get_primary_interface().name_to_tag("wght"). The string key "wght"
   is silently ignored and gives the axis default 200 (D-21, RESEARCH Pitfall 5).
