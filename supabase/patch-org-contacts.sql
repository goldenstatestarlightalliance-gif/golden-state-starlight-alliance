-- GENERATED — regenerate with: node scripts/generate-seed-sql.mjs
-- Backfills organization website/email onto an already-seeded database.
-- Idempotent: pure UPDATEs, safe to run more than once.

begin;

update organizations set website = 'sierraclub.org/sfbay', email = null where name = 'Sierra Club San Francisco Bay Chapter';
update organizations set website = 'sesb.berkeley.edu', email = null where name = 'UC Berkeley Students for the Exploration and Development of Space (SEDS)';
update organizations set website = 'santacruzdarksky.org', email = 'idasantacruzca@gmail.com' where name = 'DarkSky Santa Cruz (chapter of DarkSky International)';
update organizations set website = 'ssi.stanford.edu', email = null where name = 'Stanford Students for the Exploration and Development of Space (SEDS)';
update organizations set website = 'we-watch.org/focus/save-our-stars', email = 'nancyfemerson52@gmail.com' where name = 'DarkSky Central Coast (chapter of DarkSky International)';
update organizations set website = null, email = 'rharsey@calpoly.edu' where name = 'Cal Poly San Luis Obispo Astronomy Club';
update organizations set website = 'darkskylacounty.org', email = 'lacounty@darksky.org' where name = 'DarkSky LA County / DarkSky Joshua Tree (chapters of DarkSky International)';
update organizations set website = 'astrosociety.astro.ucla.edu', email = 'astrosociety@astro.ucla.edu' where name = 'UCLA Astronomical Society';
update organizations set website = 'sandiegosierraclub.org', email = null where name = 'Sierra Club San Diego Chapter';
update organizations set website = 'darkskysandiego.org', email = 'info@DarkSkySanDiego.org' where name = 'DarkSky San Diego County (chapter of DarkSky International)';
update organizations set website = 'sites.google.com/view/astronomyclubucsandiego', email = 'astronomyucsd@gmail.com' where name = 'UC San Diego Astronomy Club';
update organizations set website = 'sierraclub.org/mother-lode', email = null where name = 'Sierra Club Mother Lode Chapter';
update organizations set website = 'ucdastronomyclub.com', email = null where name = 'UC Davis Astronomy Club';
update organizations set website = 'sierraclub.org/Tehipite', email = null where name = 'Sierra Club Tehipite Chapter (Fresno/Madera) / Kern-Kaweah Chapter (Kern/Tulare)';
update organizations set website = 'cvafresno.org', email = 'fresnostatesustainabilityclub@gmail.com' where name = 'Fresno State environmental / astronomy club';
update organizations set website = null, email = 'SierraCollegeECOS@gmail.com' where name = 'Sierra College environmental club';
update organizations set website = 'sierraclub.org/Toiyabe', email = null where name = 'Sierra Club Toiyabe Chapter (covers the CA Eastern Sierra and Nevada)';
update organizations set website = 'sierraclub.org/Tehipite', email = null where name = 'Sierra Club Tehipite Chapter (Mariposa/Tuolumne/Madera)';
update organizations set website = null, email = 'clubsandorgs@ucmerced.edu' where name = 'UC Merced sustainability / astronomy club';
update organizations set website = 'sierraclub.org/redwood', email = null where name = 'Sierra Club Redwood Chapter';
update organizations set website = null, email = 'enst.club@humboldt.edu' where name = 'Cal Poly Humboldt environmental club';
update organizations set website = 'sierraclub.org/mother-lode', email = null where name = 'Sierra Club Mother Lode Chapter (Shasta-area groups)';
update organizations set website = null, email = 'as_sustainability@csuchico.edu' where name = 'CSU Chico (Chico State) sustainability / astronomy club';
update organizations set website = 'unr.edu/lake-tahoe', email = null where name = 'Sierra Nevada University environmental club (Tahoe area)';
update organizations set website = 'sandiegosierraclub.org', email = null where name = 'Sierra Club San Diego Chapter (Imperial Co. is in its territory)';
update organizations set website = 'imperial.edu/campus-life/campus-clubs.html', email = null where name = 'Imperial Valley College sustainability club';

commit;

-- How many organizations now have a link (expected: 26 of 68)
select count(*) filter (where website is not null or email is not null) as linked,
       count(*) as total from organizations;
