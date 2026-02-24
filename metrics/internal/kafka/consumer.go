package kafka

import (
	"bytes"
	"context"
	"io"
	"strings"

	"github.com/twmb/franz-go/pkg/kgo"
	"google.golang.org/protobuf/encoding/protodelim"

	flowpb "github.com/netsampler/goflow2/v2/pb"
)

type Consumer struct {
	client *kgo.Client
}

func NewConsumer(brokers, topic, group string) (*Consumer, error) {
	client, err := kgo.NewClient(
		kgo.SeedBrokers(strings.Split(brokers, ",")...),
		kgo.ConsumerGroup(group),
		kgo.ConsumeTopics(topic),
		kgo.ConsumeResetOffset(kgo.NewOffset().AtEnd()),
	)
	if err != nil {
		return nil, err
	}

	return &Consumer{client: client}, nil
}

func (c *Consumer) Close() {
	c.client.Close()
}

func (c *Consumer) Poll(ctx context.Context) ([]*flowpb.FlowMessage, error) {
	fetches := c.client.PollFetches(ctx)
	if err := fetches.Err(); err != nil {
		return nil, err
	}

	var flows []*flowpb.FlowMessage
	fetches.EachRecord(func(r *kgo.Record) {
		msgs := parseDelimitedProto(r.Value)
		flows = append(flows, msgs...)
	})

	return flows, nil
}

func parseDelimitedProto(data []byte) []*flowpb.FlowMessage {
	var msgs []*flowpb.FlowMessage
	reader := bytes.NewReader(data)

	for {
		msg := &flowpb.FlowMessage{}
		err := protodelim.UnmarshalFrom(reader, msg)
		if err == io.EOF {
			break
		}
		if err != nil {
			continue
		}
		msgs = append(msgs, msg)
	}

	return msgs
}
