# Pencil workflow

How to design a screen in Pencil and get it approved. What the design must look like is in the
[design skill](../.claude/skills/design/SKILL.md).

Each look has its own Pencil file in the main project folder: `concept.pen` (new concept), `classic.pen` (live
Classic look), `botanical.pen` (Botanical). Each opens with its design-system page: the app's colours, text
sizes, spacing and parts.

1. **Open the right file.** Call `get_app_state`; the Pencil tools change only the open file. If it is the wrong
   one, ask Jafar to open the right one and wait.
2. **Design from the file's own parts.** Use copies of its parts and its colour and size names, never raw values.
   To change a part, change it on the design-system page first so every screen follows. Finished when each
   screen exists at 1440px and a screenshot shows nothing cut off or misaligned.
3. **Show Jafar and wait.** Name the screens, say what each shows and which parts changed. Finished when he says
   yes; record his yes, the date and the screen names in the campaign's part note.
4. **Keep Pencil, code and skill the same.** A colour, size or part changed in Pencil changes in
   `src/lib/styles/_variables.scss` (or the component) and in the design skill in the same commit.

**Saving.** Pencil writes to disk only when the file is saved in the app (Ctrl+S). Before committing, check the
`.pen` file's modified time is newer than your last edit; if not, ask Jafar to save. Commit it in its own commit,
under a claim. Jafar or another agent may be editing the same file: read a part again just before changing it,
and leave changes you did not make as they are.
