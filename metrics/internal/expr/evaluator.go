package expr

import (
	"fmt"
	"net"

	"github.com/expr-lang/expr"
	"github.com/expr-lang/expr/vm"
	"github.com/network-monitoring/metrics/internal/flow"
)

type CompiledExpression struct {
	ID      string
	Name    string
	Program *vm.Program
}

type Env struct {
	flow.Flow

	IP          func(string) net.IP           `expr:"ip"`
	Prefix      func(string) *net.IPNet       `expr:"prefix"`
	Mac         func(string) net.HardwareAddr `expr:"mac"`
	IpInPrefix  func(net.IP, *net.IPNet) bool `expr:"ip_in_prefix"`
	IsPrivateIP func(net.IP) bool             `expr:"is_private_ip"`
	IsIPv4      func(net.IP) bool             `expr:"is_ipv4"`
	IsIPv6      func(net.IP) bool             `expr:"is_ipv6"`
}

func NewEnv(f *flow.Flow) *Env {
	return &Env{
		Flow:        *f,
		IP:          parseIP,
		Prefix:      parsePrefix,
		Mac:         parseMac,
		IpInPrefix:  ipInPrefix,
		IsPrivateIP: isPrivateIP,
		IsIPv4:      isIPv4,
		IsIPv6:      isIPv6,
	}
}

func parseIP(s string) net.IP {
	return net.ParseIP(s)
}

func parsePrefix(s string) *net.IPNet {
	_, ipNet, err := net.ParseCIDR(s)
	if err != nil {
		return nil
	}
	return ipNet
}

func parseMac(s string) net.HardwareAddr {
	hw, err := net.ParseMAC(s)
	if err != nil {
		return nil
	}
	return hw
}

func ipInPrefix(ipAddr net.IP, network *net.IPNet) bool {
	if ipAddr == nil || network == nil {
		return false
	}
	return network.Contains(ipAddr)
}

func isPrivateIP(ipAddr net.IP) bool {
	if ipAddr == nil {
		return false
	}
	return ipAddr.IsPrivate()
}

func isIPv4(ipAddr net.IP) bool {
	if ipAddr == nil {
		return false
	}
	return ipAddr.To4() != nil
}

func isIPv6(ipAddr net.IP) bool {
	if ipAddr == nil {
		return false
	}
	return ipAddr.To4() == nil
}

func CompileWithFunctions(id, name, expression string) (*CompiledExpression, error) {
	program, err := expr.Compile(expression, expr.Env(Env{}), expr.AsBool())
	if err != nil {
		return nil, fmt.Errorf("failed to compile expression %q: %w", id, err)
	}

	return &CompiledExpression{
		ID:      id,
		Name:    name,
		Program: program,
	}, nil
}

func (e *CompiledExpression) Evaluate(f *flow.Flow) (bool, error) {
	env := NewEnv(f)
	result, err := expr.Run(e.Program, env)
	if err != nil {
		return false, err
	}

	match, ok := result.(bool)
	if !ok {
		return false, fmt.Errorf("expression did not return bool")
	}

	return match, nil
}
