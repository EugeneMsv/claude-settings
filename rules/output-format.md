# Output Format

- When the user asks for a "report", "comparison", or per-item breakdown across a set (modules, files, options, risks), render it as a **Markdown table** unless asked otherwise — one row per item, columns for the dimensions being compared. Not prose paragraphs or bullet lists.
- Keep the same shape when the user says "again", "as earlier", or "for both categories" — repeat the established table format, don't re-narrate.
- Default to rendering output in chat; only write to a file when the user asks for one.
- When the user does ask for output in a file, write it there in the requested format immediately — don't render it in chat and then ask whether to save it.
