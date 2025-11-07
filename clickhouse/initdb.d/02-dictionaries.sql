CREATE DATABASE IF NOT EXISTS dictionaries;

CREATE DICTIONARY IF NOT EXISTS dictionaries.protocols (
    proto UInt8,
    name String,
    description String
)
PRIMARY KEY proto
LAYOUT(FLAT())
SOURCE (FILE(path '/var/lib/clickhouse/user_files/protocols.csv' format 'CSVWithNames'))
LIFETIME(0);
