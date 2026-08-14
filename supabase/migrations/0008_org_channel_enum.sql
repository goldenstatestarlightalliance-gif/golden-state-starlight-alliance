-- Golden State Starlight Alliance — add the 'org' channel kind (spec §5).
--
-- RUN THIS FILE ON ITS OWN, BEFORE 0009.
--
-- Postgres will not let a newly added enum value be USED in the same
-- transaction that adds it. 0009 inserts rows with kind = 'org', so the value
-- has to be committed first. Splitting it into its own file is the only
-- reliable way to guarantee that when these are pasted into the SQL editor.
--
-- Deliberately NOT wrapped in begin/commit.

alter type channel_kind add value if not exists 'org';
