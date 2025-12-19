SHOW SCHEMAS FROM polaris;
USE polaris.redpanda;
SHOW TABLES;

SELECT * FROM polaris.redpanda.events;
SELECT count(*) FROM polaris.redpanda.events;
DESCRIBE polaris.redpanda.events; 
SELECT user_id, count(*) from polaris.redpanda.events group by user_id;
SELECT * FROM polaris.redpanda."events$snapshots";
SELECT * FROM polaris.redpanda.events FOR TIMESTAMP AS OF TIMESTAMP '2025-12-11 17:16:00'; -- time travel query