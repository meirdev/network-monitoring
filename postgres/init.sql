create table accounts
(
    id varchar(32) not null primary key,
    name text not null
);

create table configs
(
    id varchar(32) not null primary key,
    account_id varchar(32) not null references accounts(id),
    name text not null,
    router_ip inet not null,
    default_sampling int
);

create type rule_type as enum ('threshold', 'zscore');

create type rule_zscore_target as enum ('bits', 'packets');

create table rules
(
    id varchar(32) not null primary key,
    account_id varchar(32) not null references accounts(id),
    name text not null,
    type rule_type not null,
    threshold_bandwidth int,
    threshold_packet int,
    zscore_target rule_zscore_target,
    duration int not null,
    prefixes cidr[] not null,
);
