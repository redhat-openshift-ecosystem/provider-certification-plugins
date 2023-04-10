// ocp-etcd-log-filters parses the logs of etcd from stdin
//
//	$ cat must-gather.local.*/*/namespaces/openshift-etcd/pods/*/etcd/etcd/logs/current.log \
//	  | ./ocp-etcd-log-filters [options]
package main

import (
	"bufio"
	"flag"
	"os"
)

func main() {

	aggregator := flag.String("aggregator", "all", "Aggregator. Valid: all, day, hour, minute. Default: all")
	flag.Parse()

	filterATTL := NewFilterApplyTookTooLong(*aggregator)

	s := bufio.NewScanner(os.Stdin)
	for s.Scan() {
		line := s.Text()
		filterATTL.ProcessLine(line)
	}

	filterATTL.Show()
}
