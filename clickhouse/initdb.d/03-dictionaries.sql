CREATE DICTIONARY IF NOT EXISTS flows.protocols (
    proto UInt8,
    name String,
    description String
)
PRIMARY KEY proto
LAYOUT(FLAT())
SOURCE (FILE(path '/var/lib/clickhouse/user_files/protocols.csv' format 'CSVWithNames'))
LIFETIME(0);


CREATE DICTIONARY IF NOT EXISTS flows.prefixes (
    id String,
    prefix String
)
PRIMARY KEY id
LAYOUT(IP_TRIE)
SOURCE (CLICKHOUSE(query 'SELECT prefix AS id, arrayJoin(prefixes) AS prefix FROM flows.rules FINAL' user 'default' password 'password'))
LIFETIME(0);
