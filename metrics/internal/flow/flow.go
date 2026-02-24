package flow

import (
	"encoding/binary"
	"net"
	"time"

	flowpb "github.com/netsampler/goflow2/v2/pb"
)

type Flow struct {
	SamplerAddress   net.IP           `expr:"sampler_address"`
	SrcAddr          net.IP           `expr:"src_addr"`
	DstAddr          net.IP           `expr:"dst_addr"`
	Etype            uint32           `expr:"etype"`
	Proto            uint32           `expr:"proto"`
	SrcPort          uint32           `expr:"src_port"`
	DstPort          uint32           `expr:"dst_port"`
	InIf             uint32           `expr:"in_if"`
	OutIf            uint32           `expr:"out_if"`
	SrcMac           net.HardwareAddr `expr:"src_mac"`
	DstMac           net.HardwareAddr `expr:"dst_mac"`
	SrcVlan          uint32           `expr:"src_vlan"`
	DstVlan          uint32           `expr:"dst_vlan"`
	VlanId           uint32           `expr:"vlan_id"`
	IpTos            uint32           `expr:"ip_tos"`
	ForwardingStatus uint32           `expr:"forwarding_status"`
	IpTtl            uint32           `expr:"ip_ttl"`
	IpFlags          uint32           `expr:"ip_flags"`
	IcmpType         uint32           `expr:"icmp_type"`
	IcmpCode         uint32           `expr:"icmp_code"`
	FragmentId       uint32           `expr:"fragment_id"`
	FragmentOffset   uint32           `expr:"fragment_offset"`
	SrcAs            uint32           `expr:"src_as"`
	DstAs            uint32           `expr:"dst_as"`
	NextHop          net.IP           `expr:"next_hop"`
	NextHopAs        uint32           `expr:"next_hop_as"`
	SrcNet           uint32           `expr:"src_net"`
	DstNet           uint32           `expr:"dst_net"`
	BgpNextHop       net.IP           `expr:"bgp_next_hop"`
	BgpCommunities   []uint32         `expr:"bgp_communities"`
	AsPath           []uint32         `expr:"as_path"`
}

type FlowWithMetrics struct {
	Flow
	TimeReceived time.Time
	TotalBytes   uint64
	TotalPackets uint64
}

func FromProto(msg *flowpb.FlowMessage, defaultSamplingRate uint64) *FlowWithMetrics {
	samplingRate := msg.SamplingRate
	if samplingRate == 0 {
		samplingRate = defaultSamplingRate
	}
	if samplingRate == 0 {
		samplingRate = 1
	}

	return &FlowWithMetrics{
		Flow: Flow{
			SamplerAddress:   net.IP(msg.SamplerAddress),
			SrcAddr:          net.IP(msg.SrcAddr),
			DstAddr:          net.IP(msg.DstAddr),
			Etype:            msg.Etype,
			Proto:            msg.Proto,
			SrcPort:          msg.SrcPort,
			DstPort:          msg.DstPort,
			InIf:             msg.InIf,
			OutIf:            msg.OutIf,
			SrcMac:           uint64ToMac(msg.SrcMac),
			DstMac:           uint64ToMac(msg.DstMac),
			SrcVlan:          msg.SrcVlan,
			DstVlan:          msg.DstVlan,
			VlanId:           msg.VlanId,
			IpTos:            msg.IpTos,
			ForwardingStatus: msg.ForwardingStatus,
			IpTtl:            msg.IpTtl,
			IpFlags:          msg.IpFlags,
			IcmpType:         msg.IcmpType,
			IcmpCode:         msg.IcmpCode,
			FragmentId:       msg.FragmentId,
			FragmentOffset:   msg.FragmentOffset,
			SrcAs:            msg.SrcAs,
			DstAs:            msg.DstAs,
			NextHop:          net.IP(msg.NextHop),
			NextHopAs:        msg.NextHopAs,
			SrcNet:           msg.SrcNet,
			DstNet:           msg.DstNet,
			BgpNextHop:       net.IP(msg.BgpNextHop),
			BgpCommunities:   msg.BgpCommunities,
			AsPath:           msg.AsPath,
		},
		TimeReceived: toTime(msg.TimeReceivedNs),
		TotalBytes:   msg.Bytes * samplingRate,
		TotalPackets: msg.Packets * samplingRate,
	}
}

func uint64ToMac(v uint64) net.HardwareAddr {
	var buf [8]byte
	binary.BigEndian.PutUint64(buf[:], v)
	return net.HardwareAddr(buf[2:])
}

func toTime(data uint64) time.Time {
	return time.Unix(int64(data/1e9), int64(data%1e9)).UTC()
}
