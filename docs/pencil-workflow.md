# Pencil workflow

How to work in the Pencil app. What a design must look like is in the
[design skill](../.claude/skills/design/SKILL.md).

1. **Open the right file.** Call `get_app_state`; the Pencil tools change only the file open in the app
   (`concept.pen` for the new concept). If it is the wrong one, ask Jafar to open the right one and wait.
2. **Change parts at the source.** To change a part, change it on the file's design-system boards first, so every
   screen using it follows. Finished when each screen's screenshot shows nothing cut off or misaligned.
3. **Show Jafar and wait.** Name the screens, say what each shows and which parts changed. When he says yes,
   record his yes, the date and the screen names in the campaign's part note.
4. **Save before committing.** Pencil writes to disk only when the file is saved in the app (Ctrl+S). Check the
   `.pen` file's modified time is newer than your last edit; if not, ask Jafar to save. Commit it in its own
   commit, under a claim.
5. **Share the file safely.** Jafar or another agent may be editing it: read a part again just before changing
   it, and leave changes you did not make as they are.
6. **Tidy up after building.** When a piece is built and matches its drawing (Built ✅ on the redesign
   checklist), delete its drafts, rejected options and comparison boards. Keep the parts boards and one final
   drawing per screen; they are the blueprint for later changes (Jafar, 2026-10-18).
