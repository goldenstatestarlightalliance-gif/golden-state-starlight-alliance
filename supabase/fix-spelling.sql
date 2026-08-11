-- Convert British to American spelling in stored text.
--
-- The site is for a California organization addressing California city
-- councils; British spelling throughout reads as careless. The source files
-- are fixed separately — this covers the text already written into the
-- database, which is what actually renders on the ordinance and city pages.
--
-- Idempotent: replace() on text that is already American changes nothing.

begin;

create or replace function americanize(t text)
returns text language sql immutable as $$
  select case when t is null then null else
    replace(replace(replace(replace(replace(replace(replace(replace(
    replace(replace(replace(replace(replace(replace(replace(replace(
      t,
      'colour', 'color'), 'Colour', 'Color'),
      'minimis', 'minimiz'), 'Minimis', 'Minimiz'),
      'organisation', 'organization'), 'Organisation', 'Organization'),
      'neighbour', 'neighbor'), 'Neighbour', 'Neighbor'),
      'centre', 'center'), 'Centre', 'Center'),
      'authorisation', 'authorization'), 'Authorisation', 'Authorization'),
      'utilis', 'utiliz'),
      'recognis', 'recogniz'),
      'behaviour', 'behavior'),
      'metres', 'meters')
  end;
$$;

update counties set
  ordinance_title   = americanize(ordinance_title),
  ordinance_summary = americanize(ordinance_summary)
where ordinance_title is not null or ordinance_summary is not null;

update ordinances set
  title   = americanize(title),
  summary = americanize(summary)
where title is not null or summary is not null;

update cities set
  ordinance_notes = americanize(ordinance_notes)
where ordinance_notes is not null;

update county_outreach set
  method          = americanize(method),
  prof_contact    = americanize(prof_contact),
  student_contact = americanize(student_contact);

update county_documents set label = americanize(label) where label is not null;

drop function americanize(text);

commit;

-- Should return zero rows.
select 'counties' as tbl, name from counties
 where ordinance_summary ~* '(colour|minimis|organisation|neighbour|centre)'
union all
select 'ordinances', title from ordinances
 where summary ~* '(colour|minimis|organisation|neighbour|centre)'
union all
select 'cities', name from cities
 where ordinance_notes ~* '(colour|minimis|organisation|neighbour|centre)';
