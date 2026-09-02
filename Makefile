# afx — bashmarks-style install.
#   make install     install to ~/.local/bin (override with PREFIX=...)
#   make uninstall   remove it
#   make test        run the bats test suite (tests/*.bats)

PREFIX ?= $(HOME)/.local
BINDIR  = $(PREFIX)/bin

# Uses a system `bats` if already on PATH (e.g. installed via a package
# manager); otherwise falls back to `npx bats`, which fetches bats-core
# on demand without adding a package.json to this bash-only repo.
BATS := $(shell command -v bats 2>/dev/null || echo "npx --yes bats")

test:
	$(BATS) tests/

install:
	install -d $(BINDIR)
	install -m 644 afx.sh $(BINDIR)/afx.sh
	install -m 755 afx $(BINDIR)/afx
	install -m 644 afx-aliases.sh $(BINDIR)/afx-aliases.sh
	@echo ''
	@echo 'Installed to $(BINDIR).'
	@echo 'For the full `afx go` (one that leaves your shell in the'
	@echo 'starred session''s directory), add this to your ~/.bashrc —'
	@echo 'above the "not interactive" guard, so that `! afx ...` also'
	@echo 'works inside Claude Code sessions:'
	@echo ''
	@echo '  source $(BINDIR)/afx.sh'
	@echo ''
	@echo 'zsh users: tab completion for afx needs the completion system'
	@echo 'loaded first. If your ~/.zshrc doesn'"'"'t already do this, add it'
	@echo 'before the `source` line above:'
	@echo ''
	@echo '  autoload -Uz compinit && compinit'
	@echo ''
	@echo '----------------------------------------------------------------'
	@echo 'NOTE: this only installs the CLI -- `afx star`/`go`/`rm` work now,'
	@echo 'but `afx list` stays empty until you also install a hook. Run the'
	@echo 'installer for whichever coding agent(s) you use:'
	@echo ''
	@echo '  make install-claude-hook   # Claude Code'
	@echo '  make install-codex-hook    # Codex'
	@echo '  make install-gemini-hook   # Gemini CLI'
	@echo '----------------------------------------------------------------'

uninstall:
	rm -f $(BINDIR)/afx.sh $(BINDIR)/afx $(BINDIR)/afx-aliases.sh

# Register the SessionEnd, UserPromptSubmit, and PostToolUse (Bash-only)
# hooks in every ~/.claude* settings.json (backs each up to
# settings.json.bak first). Browse the journal with `afx list`, background
# jobs with `afx jobs`.
install-claude-hook:
	install -m 755 hooks/afx-claude-sessionend $(BINDIR)/afx-claude-sessionend
	install -m 755 hooks/afx-claude-summarize-async $(BINDIR)/afx-claude-summarize-async
	install -m 755 hooks/afx-claude-userpromptsubmit $(BINDIR)/afx-claude-userpromptsubmit
	install -m 755 hooks/afx-claude-posttooluse $(BINDIR)/afx-claude-posttooluse
	@for d in $(HOME)/.claude $(HOME)/.claude-*; do \
	  [ -d $$d ] || continue; \
	  s=$$d/settings.json; [ -f $$s ] || echo '{}' > $$s; \
	  cp $$s $$s.bak; \
	  jq --arg cmd "$(BINDIR)/afx-claude-sessionend" --arg cmd2 "$(BINDIR)/afx-claude-userpromptsubmit" \
	     --arg cmd3 "$(BINDIR)/afx-claude-posttooluse" \
	     '.hooks.SessionEnd = ((.hooks.SessionEnd // []) | map(select((.hooks[0].command // "") != $$cmd))) + [{"hooks": [{"type": "command", "command": $$cmd}]}] | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(select((.hooks[0].command // "") != $$cmd2))) + [{"hooks": [{"type": "command", "command": $$cmd2}]}] | .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select((.hooks[0].command // "") != $$cmd3))) + [{"matcher": "Bash", "hooks": [{"type": "command", "command": $$cmd3}]}]' \
	    $$s.bak > $$s.new && mv $$s.new $$s && echo "hooks registered in $$s"; \
	done

uninstall-claude-hook:
	@for d in $(HOME)/.claude $(HOME)/.claude-*; do \
	  s=$$d/settings.json; [ -f $$s ] || continue; \
	  cp $$s $$s.bak; \
	  jq --arg cmd "$(BINDIR)/afx-claude-sessionend" --arg cmd2 "$(BINDIR)/afx-claude-userpromptsubmit" \
	     --arg cmd3 "$(BINDIR)/afx-claude-posttooluse" \
	     '.hooks.SessionEnd = ((.hooks.SessionEnd // []) | map(select((.hooks[0].command // "") != $$cmd))) | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(select((.hooks[0].command // "") != $$cmd2))) | .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select((.hooks[0].command // "") != $$cmd3)))' \
	    $$s.bak > $$s.new && mv $$s.new $$s && echo "hooks removed from $$s"; \
	done
	rm -f $(BINDIR)/afx-claude-sessionend $(BINDIR)/afx-claude-summarize-async $(BINDIR)/afx-claude-userpromptsubmit $(BINDIR)/afx-claude-posttooluse

# Register the SessionEnd and UserPromptSubmit hooks in every ~/.codex*
# hooks.json (backs each up to hooks.json.bak first). No PostToolUse/jobs
# equivalent: Codex's shell tool has no run_in_background-style flag to
# key off of, so `afx jobs` stays Claude Code-only. Codex will prompt to
# trust the new hooks the first time an interactive session hits them
# after this runs.
install-codex-hook:
	install -m 755 hooks/afx-codex-sessionend $(BINDIR)/afx-codex-sessionend
	install -m 755 hooks/afx-codex-summarize-async $(BINDIR)/afx-codex-summarize-async
	install -m 755 hooks/afx-codex-userpromptsubmit $(BINDIR)/afx-codex-userpromptsubmit
	@for d in $(HOME)/.codex $(HOME)/.codex-*; do \
	  [ -d $$d ] || continue; \
	  h=$$d/hooks.json; [ -f $$h ] || echo '{}' > $$h; \
	  cp $$h $$h.bak; \
	  jq --arg cmd "$(BINDIR)/afx-codex-sessionend" --arg cmd2 "$(BINDIR)/afx-codex-userpromptsubmit" \
	     '.hooks.SessionEnd = ((.hooks.SessionEnd // []) | map(select((.hooks[0].command // "") != $$cmd))) + [{"hooks": [{"type": "command", "command": $$cmd, "timeout": 3}]}] | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(select((.hooks[0].command // "") != $$cmd2))) + [{"hooks": [{"type": "command", "command": $$cmd2}]}]' \
	    $$h.bak > $$h.new && mv $$h.new $$h && echo "codex hooks registered in $$h"; \
	done

uninstall-codex-hook:
	@for d in $(HOME)/.codex $(HOME)/.codex-*; do \
	  h=$$d/hooks.json; [ -f $$h ] || continue; \
	  cp $$h $$h.bak; \
	  jq --arg cmd "$(BINDIR)/afx-codex-sessionend" --arg cmd2 "$(BINDIR)/afx-codex-userpromptsubmit" \
	     '.hooks.SessionEnd = ((.hooks.SessionEnd // []) | map(select((.hooks[0].command // "") != $$cmd))) | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(select((.hooks[0].command // "") != $$cmd2)))' \
	    $$h.bak > $$h.new && mv $$h.new $$h && echo "codex hooks removed from $$h"; \
	done
	rm -f $(BINDIR)/afx-codex-sessionend $(BINDIR)/afx-codex-summarize-async $(BINDIR)/afx-codex-userpromptsubmit

# Register the SessionEnd and BeforeAgent hooks (Gemini's UserPromptSubmit
# equivalent) in ~/.gemini/settings.json (backed up to .bak first). Only
# ~/.gemini itself -- unlike Claude/Codex, Gemini CLI has no env var to
# point it at a different home, so there's nothing to scan for multiple
# accounts. No PostToolUse/jobs equivalent (same reasoning as Codex), and
# no afx-star-from-a-plain-shell fallback either: Gemini's session files
# don't record cwd anywhere the hook payload isn't the one telling us --
# see README's "Session journal" section for the full explanation.
install-gemini-hook:
	install -m 755 hooks/afx-gemini-sessionend $(BINDIR)/afx-gemini-sessionend
	install -m 755 hooks/afx-gemini-summarize-async $(BINDIR)/afx-gemini-summarize-async
	install -m 755 hooks/afx-gemini-beforeagent $(BINDIR)/afx-gemini-beforeagent
	@d=$(HOME)/.gemini; \
	s=$$d/settings.json; [ -d $$d ] || mkdir -p $$d; [ -f $$s ] || echo '{}' > $$s; \
	cp $$s $$s.bak; \
	jq --arg cmd "$(BINDIR)/afx-gemini-sessionend" --arg cmd2 "$(BINDIR)/afx-gemini-beforeagent" \
	   '.hooks.SessionEnd = ((.hooks.SessionEnd // []) | map(select((.hooks[0].command // "") != $$cmd))) + [{"hooks": [{"type": "command", "command": $$cmd}]}] | .hooks.BeforeAgent = ((.hooks.BeforeAgent // []) | map(select((.hooks[0].command // "") != $$cmd2))) + [{"hooks": [{"type": "command", "command": $$cmd2}]}]' \
	  $$s.bak > $$s.new && mv $$s.new $$s && echo "gemini hooks registered in $$s"

uninstall-gemini-hook:
	@d=$(HOME)/.gemini; \
	s=$$d/settings.json; [ -f $$s ] || exit 0; \
	cp $$s $$s.bak; \
	jq --arg cmd "$(BINDIR)/afx-gemini-sessionend" --arg cmd2 "$(BINDIR)/afx-gemini-beforeagent" \
	   '.hooks.SessionEnd = ((.hooks.SessionEnd // []) | map(select((.hooks[0].command // "") != $$cmd))) | .hooks.BeforeAgent = ((.hooks.BeforeAgent // []) | map(select((.hooks[0].command // "") != $$cmd2)))' \
	  $$s.bak > $$s.new && mv $$s.new $$s && echo "gemini hooks removed from $$s"
	rm -f $(BINDIR)/afx-gemini-sessionend $(BINDIR)/afx-gemini-summarize-async $(BINDIR)/afx-gemini-beforeagent

.PHONY: install uninstall install-claude-hook uninstall-claude-hook install-codex-hook uninstall-codex-hook install-gemini-hook uninstall-gemini-hook test
