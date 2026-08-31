# afx — bashmarks-style install.
#   make install     install to ~/.local/bin (override with PREFIX=...)
#   make uninstall   remove it

PREFIX ?= $(HOME)/.local
BINDIR  = $(PREFIX)/bin

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

uninstall:
	rm -f $(BINDIR)/afx.sh $(BINDIR)/afx $(BINDIR)/afx-aliases.sh

# Register the SessionEnd, UserPromptSubmit, and PostToolUse (Bash-only)
# hooks in every ~/.claude* settings.json (backs each up to
# settings.json.bak first). Browse the journal with `afx list`, background
# jobs with `afx jobs`.
install-hook:
	install -m 755 hooks/afx-sessionend $(BINDIR)/afx-sessionend
	install -m 755 hooks/afx-summarize-async $(BINDIR)/afx-summarize-async
	install -m 755 hooks/afx-userpromptsubmit $(BINDIR)/afx-userpromptsubmit
	install -m 755 hooks/afx-posttooluse $(BINDIR)/afx-posttooluse
	@for d in $(HOME)/.claude $(HOME)/.claude-*; do \
	  [ -d $$d ] || continue; \
	  s=$$d/settings.json; [ -f $$s ] || echo '{}' > $$s; \
	  cp $$s $$s.bak; \
	  jq --arg cmd "$(BINDIR)/afx-sessionend" --arg cmd2 "$(BINDIR)/afx-userpromptsubmit" \
	     --arg cmd3 "$(BINDIR)/afx-posttooluse" \
	     '.hooks.SessionEnd = ((.hooks.SessionEnd // []) | map(select((.hooks[0].command // "") != $$cmd))) + [{"hooks": [{"type": "command", "command": $$cmd}]}] | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(select((.hooks[0].command // "") != $$cmd2))) + [{"hooks": [{"type": "command", "command": $$cmd2}]}] | .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select((.hooks[0].command // "") != $$cmd3))) + [{"matcher": "Bash", "hooks": [{"type": "command", "command": $$cmd3}]}]' \
	    $$s.bak > $$s.new && mv $$s.new $$s && echo "hooks registered in $$s"; \
	done

uninstall-hook:
	@for d in $(HOME)/.claude $(HOME)/.claude-*; do \
	  s=$$d/settings.json; [ -f $$s ] || continue; \
	  cp $$s $$s.bak; \
	  jq --arg cmd "$(BINDIR)/afx-sessionend" --arg cmd2 "$(BINDIR)/afx-userpromptsubmit" \
	     --arg cmd3 "$(BINDIR)/afx-posttooluse" \
	     '.hooks.SessionEnd = ((.hooks.SessionEnd // []) | map(select((.hooks[0].command // "") != $$cmd))) | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(select((.hooks[0].command // "") != $$cmd2))) | .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select((.hooks[0].command // "") != $$cmd3)))' \
	    $$s.bak > $$s.new && mv $$s.new $$s && echo "hooks removed from $$s"; \
	done
	rm -f $(BINDIR)/afx-sessionend $(BINDIR)/afx-summarize-async $(BINDIR)/afx-userpromptsubmit $(BINDIR)/afx-posttooluse

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

.PHONY: install uninstall install-hook uninstall-hook install-codex-hook uninstall-codex-hook
