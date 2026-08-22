---
name: technical-writing
description: >-
  Google Technical Writing style rules for technical prose: READMEs, design
  docs, PR descriptions, commit messages, doc comments, and code comments.
  Load when writing or editing any technical documentation or substantial
  prose so the wording follows the checklist below.
---

# Technical Writing

Apply these rules when writing or editing technical prose. They follow Google's
[Technical Writing](https://developers.google.com/tech-writing) courses.

## Words

- Define an unfamiliar term before its first use, or link to an existing definition.
- Use the same term for the same concept every time. Do not switch synonyms.
- Give an acronym its full expansion on first use, then use the acronym.
- Replace an ambiguous pronoun (`it`, `they`, `this`, `that`) with the noun it refers to when the reference is more than a few words away.

## Active voice

- Prefer active voice over passive voice. Name the actor before the verb.
- Prefer strong verbs over weak verbs plus a noun.
  - BAD: `perform a calculation of the total`
  - GOOD: `calculate the total`
- Reduce `there is` and `there are` openings. Start with the real subject instead.

## Clear sentences

- Express one idea per sentence. Split a long sentence into several short ones.
- Convert a long sentence that lists conditions or steps into a list.
- Remove filler that adds no information, such as `basically`, `really`, or `in order to`.
- Put the main point at the start of the sentence, not buried after clauses.

## Paragraphs

- Start each paragraph with a topic sentence that states its main point.
- Keep each paragraph to one topic. Move an unrelated idea to its own paragraph.
- Limit a paragraph to roughly three to five sentences.
- Answer what, why, and how for the reader within the surrounding paragraphs.

## Lists and tables

Prefer a bulleted or numbered list over a run-on paragraph of related items so
readers can scan the content.

- Use a bulleted list when the order of items does not matter.
- Use a numbered list when the order matters, such as steps or ranked items.
- Introduce each list with a sentence that says what the list represents, and end that sentence with a colon.
- Keep list items parallel in grammar, capitalization, and punctuation.
- Start each item of a numbered list with an imperative verb, such as "Download", "Configure", or "Start".
- Avoid embedded (run-in) lists inside a sentence. Break them out into a real list.
- Use a table when each item has several comparable attributes. Give every column a clear heading.

## Audience

- Identify the audience and write to their level of prior knowledge.
- State prerequisites before the steps that depend on them.
- Prefer concrete, verifiable statements over vague claims.
  - BAD: `The build is usually fast.`
  - GOOD: `The build finishes in under 30 seconds on a clean checkout.`
