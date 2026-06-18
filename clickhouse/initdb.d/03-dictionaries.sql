CREATE DICTIONARY IF NOT EXISTS flows.protocols
(
    `proto` UInt8,
    `name` String,
    `description` String
)
PRIMARY KEY proto
SOURCE(FILE(PATH '/var/lib/clickhouse/user_files/protocols.csv' FORMAT 'CSVWithNames'))
LIFETIME(MIN 0 MAX 0)
LAYOUT(FLAT());

CREATE DICTIONARY IF NOT EXISTS flows.prefixes
(
    `id` String,
    `prefix` String
)
PRIMARY KEY id
SOURCE(CLICKHOUSE(QUERY 'SELECT prefix AS id, arrayJoin(prefixes) AS prefix FROM flows.rules FINAL' USER 'default' PASSWORD 'password'))
LIFETIME(MIN 0 MAX 0)
LAYOUT(IP_TRIE);
