package plugin

import "sort"

// TestProgress handle the test state.
type TestProgress struct {
	TestName        string
	StartedAt       string
	EndAt           string
	TimeTook        string
	TimeTookSeconds float64
	Result          string
}

// TestProgressList is a list of test instanzas implementing Sort operations.
type TestProgressList []TestProgress

// rankTestsByTimeTaken sorts the tests by time taken.
func rankTestsByTimeTaken(wordFrequencies map[string]*TestProgress, rankType string, reverse bool) TestProgressList {
	pl := make(TestProgressList, len(wordFrequencies))
	i := 0
	for _, v := range wordFrequencies {
		pl[i] = *v
		i++
	}
	if reverse {
		sort.Sort(sort.Reverse(pl))
	} else {
		sort.Sort(pl)
	}

	return pl
}

func (p TestProgressList) Len() int { return len(p) }
func (p TestProgressList) Less(i, j int) bool {
	return p[i].TimeTookSeconds < p[j].TimeTookSeconds
}
func (p TestProgressList) Swap(i, j int) { p[i], p[j] = p[j], p[i] }
