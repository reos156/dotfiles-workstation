# Custom spell words

`custom-words.txt` is the auditable source list for genuinely personal terms. It is intentionally empty: the source machine's three text files are bulk English/Spanish dictionary exports, so custom provenance cannot be established defensibly.

Add one reviewed word per line. To test regeneration without committing generated data:

```bash
nvim --headless -u NONE \
  -c "mkspell! /tmp/dotfiles-custom.utf-8 ${XDG_CONFIG_HOME:-$HOME/.config}/nvim/spell/custom-words.txt" \
  -c qa
```

Generated `.spl` files remain untracked. Do not copy system dictionaries into this directory.
