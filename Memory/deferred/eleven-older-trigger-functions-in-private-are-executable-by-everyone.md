# Older private trigger functions retain PUBLIC execute

- **Priority:** P3
- **Why postponed:** Eleven legacy Client/collaboration trigger functions have inconsistent grants, but plain callers cannot execute trigger functions successfully.
- **Reactivate when:** Those schemas are touched or an app-wide grant sweep begins.
- **Constraint:** Revoke grants in one approved migration and verify triggers still fire.
- **Pointer:** Inspect private trigger-function grants in the current database before acting.
