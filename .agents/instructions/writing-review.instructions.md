---
description: "Use when writing or revising durable writing: PR descriptions and Markdown docs for a repo, wiki, or notes."
---

# Writing

A durable document is anything people will read after this session ends: a PR
description, code comments, or a Markdown doc in a repo, a wiki, or my notes.
Chat replies and scratch notes such as plans or to-do lists don't count.

Have a fresh reader critique or revise it's prose and content:

1. Gather the facts and write the draft yourself. If the document already
   exists, start from its current text and keep my wording unless it's wrong—or
   I've asked you to change it.
2. Start a background subagent on `gemini-4-carbon`. Paste into its prompt the
   draft, the source it describes (diff, work items; excerpt what's long), who
   will read it, and any preferences I've stated for that kind of document.
3. Gemini can re-write or suggest edits. Tell it to use no tools, not even for a
   repo's required reading, and to ask you about claims it can't check.
4. Apply the points you agree with, and check every factual change, including
   deletions, against the source. Look up its questions there too; fix what's
   wrong, and answer in the draft what readers would also ask.
5. Review at most 3 times, with lower limits for less importing writing. For
   another round, send the same subagent the revised draft and your answers.
   Stop early if you reject the remaining points.

Skip this for trivial edits like typo fixes.
