CREATE FUNCTION IF NOT EXISTS BytesToIPString AS (addr) ->
(
    -- if the first 12 bytes are zero, then it's an IPv4 address, otherwise it's an IPv6 address
    if(reinterpretAsUInt128(substring(reverse(addr), 1, 12)) = 0, IPv4NumToString(reinterpretAsUInt32(substring(reverse(addr), 13, 4))), IPv6NumToString(addr))
);

CREATE FUNCTION IF NOT EXISTS NumToFlowTypeString AS (type) ->
(
    transform(type, [0, 1, 2, 3, 4], ['UNKNOWN', 'SFLOW_5', 'NETFLOW_V5', 'NETFLOW_V9', 'IPFIX'], toString(type))
);

CREATE FUNCTION IF NOT EXISTS NumToETypeString AS (etype) ->
(
    transform(etype, [0x800, 0x806, 0x86dd], ['IPv4', 'ARP', 'IPv6'], toString(etype))
);

CREATE FUNCTION IF NOT EXISTS NumToTcpFlagsString AS (tcp_flags) ->
(
    if(tcp_flags = 0, 'EMPTY', arrayStringConcat(arrayMap(x -> transform(x, [1, 2, 4, 8, 16, 32, 64, 128, 256, 512], ['FIN', 'SYN', 'RST', 'PSH', 'ACK', 'URG', 'ECN', 'CWR', 'NONCE', 'RESERVED'], toString(x)), bitmaskToArray(tcp_flags)), '+'))
);

CREATE FUNCTION IF NOT EXISTS NumToForwardingStatusString AS (forwarding_status) ->
(
    transform(if(forwarding_status >= 64, bitShiftRight(forwarding_status, 7), forwarding_status), [0, 1, 2, 3], ['UNKNOWN', 'FORWARDED', 'DROPPED', 'CONSUMED'], toString(forwarding_status))
);

CREATE FUNCTION IF NOT EXISTS IPStringToNum AS (ip) ->
(
    if(position(ip, '.') <> 0, toUInt128(IPv4StringToNum(ip)), toUInt128(IPv6StringToNum(ip)))
);

CREATE FUNCTION IF NOT EXISTS NumToProtoString AS (proto) ->
(
    dictGetOrDefault('dictionaries.protocols', 'name', proto, toString(proto))
);
