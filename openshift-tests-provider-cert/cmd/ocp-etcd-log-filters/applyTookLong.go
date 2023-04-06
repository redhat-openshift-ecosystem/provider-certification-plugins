package main

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"text/tabwriter"
)

// LogPayloadETCD parses the etcd log file to extract insights
// {"level":"warn","ts":"2023-03-01T15:14:22.192Z",
// "caller":"etcdserver/util.go:166",
// "msg":"apply request took too long",
// "took":"231.023586ms","expected-duration":"200ms",
// "prefix":"read-only range ",
// "request":"key:\"/kubernetes.io/configmaps/kube-system/kube-controller-manager\" ",
// "response":"range_response_count:1 size:608"}
type LogPayloadETCD struct {
	Took      string `json:"took"`
	Timestamp string `json:"ts"`
}

type BucketGroup struct {
	Bukets1s    Buckets
	Bukets500ms Buckets
}

type FilterApplyTookTooLong struct {
	Name    string
	GroupBy string
	Group   map[string]*BucketGroup

	// filter config
	lineFilter     string
	reLineSplitter *regexp.Regexp
	reMili         *regexp.Regexp
	reSec          *regexp.Regexp
	reTsMin        *regexp.Regexp
	reTsHour       *regexp.Regexp
	reTsDay        *regexp.Regexp
}

func NewFilterApplyTookTooLong(aggregator string) *FilterApplyTookTooLong {
	var filter FilterApplyTookTooLong

	filter.Name = "ApplyTookTooLong"
	filter.GroupBy = aggregator
	filter.Group = make(map[string]*BucketGroup)

	filter.lineFilter = "apply request took too long"
	filter.reLineSplitter, _ = regexp.Compile(`^\d+-\d+-\d+T\d+:\d+:\d+.\d+Z `)
	filter.reMili, _ = regexp.Compile("([0-9]+.[0-9]+)ms")
	filter.reSec, _ = regexp.Compile("([0-9]+.[0-9]+)s")
	filter.reTsMin, _ = regexp.Compile(`^(\d+-\d+-\d+T\d+:\d+):\d+.\d+Z`)
	filter.reTsHour, _ = regexp.Compile(`^(\d+-\d+-\d+T\d+):\d+:\d+.\d+Z`)
	filter.reTsDay, _ = regexp.Compile(`^(\d+-\d+-\d+)T\d+:\d+:\d+.\d+Z`)

	return &filter
}

func (f *FilterApplyTookTooLong) ProcessLine(line string) {

	// filter by required filter
	if !strings.Contains(line, f.lineFilter) {
		return
	}

	// split timestamp
	split := f.reLineSplitter.Split(line, -1)
	if len(split) < 1 {
		return
	}

	// parse json
	lineParsed := LogPayloadETCD{}
	json.Unmarshal([]byte(split[1]), &lineParsed)

	if match := f.reMili.MatchString(lineParsed.Took); match { // Extract milisseconds
		matches := f.reMili.FindStringSubmatch(lineParsed.Took)
		if len(matches) == 2 {
			if v, err := strconv.ParseFloat(matches[1], 64); err == nil {
				f.insertBucket(v, lineParsed.Timestamp)
			}
		}
	} else if match := f.reSec.MatchString(lineParsed.Took); match { // Extract seconds
		matches := f.reSec.FindStringSubmatch(lineParsed.Took)
		if len(matches) == 2 {
			if v, err := strconv.ParseFloat(matches[1], 64); err == nil {
				v = v * 1000
				f.insertBucket(v, lineParsed.Timestamp)
			}
		}
	} else {
		fmt.Printf("No bucket for: %v\n", lineParsed.Took)
	}
}

func (f *FilterApplyTookTooLong) insertBucket(v float64, ts string) {
	var group *BucketGroup
	var aggrKey string

	if f.GroupBy == "hour" {
		aggrValue := "all"
		if match := f.reTsHour.MatchString(ts); match {
			matches := f.reTsHour.FindStringSubmatch(ts)
			aggrValue = matches[1]
		}
		aggrKey = aggrValue
	} else if f.GroupBy == "day" {
		aggrValue := "all"
		if match := f.reTsDay.MatchString(ts); match {
			matches := f.reTsDay.FindStringSubmatch(ts)
			aggrValue = matches[1]
		}
		aggrKey = aggrValue
	} else if f.GroupBy == "minute" || f.GroupBy == "min" {
		aggrValue := "all"
		if match := f.reTsMin.MatchString(ts); match {
			matches := f.reTsMin.FindStringSubmatch(ts)
			aggrValue = matches[1]
		}
		aggrKey = aggrValue
	} else {
		aggrKey = f.GroupBy
	}

	if _, ok := f.Group[aggrKey]; !ok {
		f.Group[aggrKey] = &BucketGroup{}
		group = f.Group[aggrKey]
		group.Bukets1s = NewBuckets(buckets1s())
		group.Bukets500ms = NewBuckets(buckets500ms())
	} else {
		group = f.Group[aggrKey]
	}

	b1s := group.Bukets1s
	b500ms := group.Bukets500ms

	switch {
	case v < 200.0:
		k := "low-200"
		b1s[k] += 1
		b500ms[k] += 1
	case ((v >= 200.0) && (v <= 299.0)):
		k := "200-300"
		b1s[k] += 1
		b500ms[k] += 1
	case ((v >= 300.0) && (v <= 399.0)):
		k := "300-400"
		b1s[k] += 1
		b500ms[k] += 1
	case ((v >= 400.0) && (v <= 499.0)):
		k := "400-500"
		b1s[k] += 1
		b500ms[k] += 1
	case ((v >= 500.0) && (v <= 599.0)):
		k := "500-600"
		b1s[k] += 1
		k = "500-inf"
		b500ms[k] += 1
	case ((v >= 600.0) && (v <= 699.0)):
		k := "600-700"
		b1s[k] += 1
		k = "500-inf"
		b500ms[k] += 1
	case ((v >= 700.0) && (v <= 799.0)):
		k := "700-800"
		b1s[k] += 1
		k = "500-inf"
		b500ms[k] += 1
	case ((v >= 800.0) && (v <= 899.0)):
		k := "800-900"
		b1s[k] += 1
		k = "500-inf"
		b500ms[k] += 1
	case ((v >= 900.0) && (v <= 999.0)):
		k := "900-1s"
		b1s[k] += 1
		k = "500-inf"
		b500ms[k] += 1
	case (v >= 1000.0):
		k := "1s-inf"
		b1s[k] += 1

		k = "500-inf"
		b500ms[k] += 1
	default:
		k := "unkw"
		b1s[k] += 1
		b500ms[k] += 1
	}
	k := "all"

	b1s[k] += 1
	b500ms[k] += 1
}

func (f *FilterApplyTookTooLong) Show() {

	fmt.Printf("> Filter Name: %s\n", f.Name)

	fmt.Printf("> Group by: %s\n", f.GroupBy)
	for aggr, group := range f.Group {
		if aggr != "all" {
			fmt.Printf("\n>> %s\n", aggr)
		}
		b1s := group.Bukets1s
		b500ms := group.Bukets500ms

		tbWriter := tabwriter.NewWriter(os.Stdout, 0, 8, 1, '\t', tabwriter.AlignRight)
		show := func(k string) {
			v := b1s[k]
			perc := fmt.Sprintf("(%.3f %%)", (float64(v)/float64(b1s["all"]))*100)
			if k == "all" {
				perc = ""
			}
			fmt.Fprintf(tbWriter, "%s\t %d\t%s\n", k, v, perc)
		}

		fmt.Println(">>> Summary <<<")
		show("all")

		v500 := b500ms["500-inf"]
		perc500inf := (float64(v500) / float64(b500ms["all"])) * 100
		fmt.Fprintf(tbWriter, ">500ms\t %d\t(%.3f %%)\n", v500, perc500inf)
		fmt.Fprintf(tbWriter, "---\n")

		fmt.Println(">>> Buckets <<<")
		show("low-200")
		show("200-300")
		show("300-400")
		show("400-500")
		show("500-600")
		show("600-700")
		show("700-800")
		show("800-900")
		show("900-1s")
		show("1s-inf")
		show("unkw")

		tbWriter.Flush()

	}
}
