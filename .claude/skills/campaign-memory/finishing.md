# Finish a part or campaign, or put work aside

## Finish a part

A part is finished when its done-check passes in the integrated project (`main`). Then:

1. Move lasting decisions into the plan or an ADR, and link the part's proof from the plan's **Sources**, so it
   stays reachable after the note is gone.
2. Mark the part `Done <date>` in the roadmap and delete its note. When every part in a group file is done,
   replace the file with one roadmap line.
3. Point `NOW.md` at the next part, and say what it waits for if it cannot start yet.
4. Commit, and release the claim or hand it over before starting another part.

## Finish the campaign

The campaign is finished when every required part is done, the plan's success checks pass in the integrated
project, and nothing the plan agreed is known to be broken. Keep any open release condition or owner check
visible in the plan. Change the plan's **Status:** line to `Built and verified <date>`, put later-version
work the plan has not already excluded into deferred, delete the campaign's index row and folder, and commit.

## Put work aside

1. Search `Memory/deferred/INDEX.md` for the same work and update a match rather than adding a second record.
2. Otherwise add a row, and a note from [the template](templates/deferred.md): why it waits, what brings it
   back, and constraints already known.
3. Delete the row and note when the work is done, dropped, or taken up by a campaign.

Take up deferred work only when Jafar or a note names it.
