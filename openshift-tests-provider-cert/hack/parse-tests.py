#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OpenShift tests discovery
    Discovery e2e tests for each suite, parse, classify
    and export to json.

TODO: add examples.

Using it on executor.sh, add:

# Simple filter to use like those on openshif-tests
# $ openshift-tests run --dry-run all |grep '\[sig-storage\]' |openshift-tests run -f -
elif [[ ! -z ${CUSTOM_TEST_FILTER_SIG:-} ]]; then
    os_log_info "Generating tests for SIG [${CUSTOM_TEST_FILTER_SIG}]..."
    mkdir tmp/
    ./parse-tests.py \
        --filter-suites all \
        --filter-key sig \
        --filter-value "${CUSTOM_TEST_FILTER_SIG}"

    os_log_info "#executor>Running"
    openshift-tests run \
        --junit-dir ${RESULTS_DIR} \
        -f ./tmp/openshift-e2e-suites.txt \
        | tee -a "${RESULTS_PIPE}" || true
    """
import sys
import json
import csv
import re
import argparse
import subprocess
import logging
#from this import d


bin_openshift_tests="openshift-tests"
base_output_file="openshift-tests-suites"
default_empty=("-"*3)

#
# Gather and Parser
#
def gather_suite_tests(suite):
    try:
        resp = subprocess.check_output(f"{bin_openshift_tests} run --dry-run {suite}", shell=True)
        return resp.decode("utf-8").split('\n')
    except subprocess.CalledProcessError as e:
        if e.returncode == 127:
            print("Please make sure the 'openshift-tests' binary exists")
            print("Did you build it by running ./build.sh script?")
        else:
            print(f"One or more error was found when collecting the list of tests for suite [{suite}]")
            print(f"Make sure you are able to run this command: {e.cmd}")
        sys.exit(e.returncode)


def parser_suite_tests(suite, tests):
    """
    Extract metadata from test name
    """
    parsed_tests = []
    for test_name in tests:
        if test_name.strip() is "":
            continue
        test = {
            "name": test_name,
            "name_parsed": "",
            "tags": [],
            "filters": {
                "in_kubernetes_conformance": default_empty,
                "in_openshift_conformance": default_empty,
            }
        }
        name = test_name

        # extract tags ('[<any char>]') from test name
        m_tags = re.findall(r'\[(.*?)\]+', test_name)
        for tag in m_tags:

            # discovery name: remove 'tags'
            name = name.replace(f"[{tag}]", "")

            t = tag.split(':')

            # build filters
            build_filters_from_tags(test['filters'], t)

            # set empty keys
            if len(t) == 1:
                test['tags'].append({t[0]: ''})
                continue

            # ToDo: tag could be a tuple
            test['tags'].append({t[0]: ' '.join(t[1:])})

        # Save the parsed name (without tags)
        test['name_parsed'] = name.strip('"').strip()

        parsed_tests.append(test)

    return parsed_tests


#
# Filter
#
def build_filters_from_tags(filters, tag):

    if tag[0] == 'Conformance':
        filters['is_conformance'] = True
        return

    if tag[0].startswith('sig'):
        filters['sig'] = tag[0]
        return

    if (tag[0] == 'Suite') and tag[1] == 'k8s':
        filters['suite_k8s'] = True
        return

    if (tag[0] == 'Suite'):
        filters['suite'] = (' '.join(tag[1:]))
        return

    if (tag[0] == 'suite_cmd'):
        return


def build_filters_intersection(suites, suite1, suite2):
    """
    Check if tests from suite1 is in suite2
    """
    for s in suites:
        if s['name'] == suite1:
            tests_suite1 = s['tests']

        if s['name'] == suite2:
            tests_suite2 = s['tests']

    filter_name = (f"in_{suite1.replace('/', '_')}")

    for t1 in tests_suite1:
        #t1['filters'][filter_name] = ''
        for t2 in tests_suite2:
            #t2['filters'][filter_name] = False
            if t1['name'] == t2['name']:
                t2['filters'][filter_name] = True


def to_tags_str(tags):
    """
    Build inline tags - as original: [key(|:value)]
    """
    tags_str = ""
    for t in tags:
        for key in t:
            if t[key] == '':
                tags_str+=(f"[{key}] ")
                continue
            tags_str+=(f"[{key}:{t[key]}] ")
    return tags_str


def build_field_filters(suites, filter_field_prefix):
    filter_k = {}
    for s in suites:
        for t in s['tests']:
            for f in t['filters']:
                filter_k[f"{filter_field_prefix}{f}"] = ''
    return list(filter_k.keys())

def filter_kv(payload, kv):
    new_suite = {
        "name": "filtered",
        "tests": []
    }
    k, v = kv
    for s in payload['suites']:
        for t in s['tests']:
            if k in t['filters']:
                if t['filters'][k] == v:
                    new_suite['tests'].append(t)

    return {
        "suites": [new_suite]
    }

#
# Exporters
#
def export_to_csv(payload, odir):
    """Export tests to CSV table with properly filters discovered by metadata
    """
    with open(f'{odir}/{base_output_file}.csv', 'w', newline='') as csvfile:

        fieldnames = ['suite', 'name_alias', 'tags', 'name']

        ffield_prefix = "f_"
        ffilters = build_field_filters(payload['suites'], ffield_prefix)

        fieldnames = fieldnames + ffilters

        writer = csv.DictWriter(csvfile, fieldnames=fieldnames, delimiter=';')
        writer.writeheader()
        for suite in payload['suites']:
            for test in suite['tests']:
                row = {
                    'suite': suite['name'],
                    'name_alias': test['name_parsed'],
                    'tags': to_tags_str(test['tags']),
                    'name': test['name']
                }
                for f in ffilters:
                    row[f] = (test['filters'].get(f.strip(ffield_prefix), default_empty))
                writer.writerow(row)

    print(f"CSV file saved in {odir}/{base_output_file}.csv")


def export_to_json(payload, odir):
    """Export tests as json with it's metadata
    """
    with open(f'{odir}/{base_output_file}.json', 'w') as outfile:
        json.dump(payload, outfile)
    print(f"Json file saved in {odir}/{base_output_file}.json")


def export_to_txt(payload, odir):
    """Export tests name to text file to be able to reproduce on 'openshift-tests run -f'.
    """
    with open(f'{odir}/{base_output_file}.txt', 'w') as outfile:
        for s in payload['suites']:
            for t in s['tests']:
                outfile.write(f"{t['name']}\n")
    print(f"Text file saved in {odir}/{base_output_file}.txt")

#
# Exporter entity
#
class TestsExporter(object):
    suites = []
    payload = {
        "suites": []
    }
    output = {
        "file": "",
        "dir": "",
        "types": {
            "json": False,
            "csv": False,
            "txt": False
        }
    }
    def __init__(self, suites=[]):
        self.suites = suites

    def gather_tests(self):
        for suite_name in self.suites:
            tests = gather_suite_tests(suite_name)
            parsed_tests = parser_suite_tests(suite_name, tests)
            self.payload["suites"].append({
                "name": suite_name,
                "tests": parsed_tests
            })

    def build_filter_intersection(self):
        # improve filters
        build_filters_intersection(self.payload['suites'], self.suites[0], self.suites[1])
        build_filters_intersection(self.payload['suites'], self.suites[1], self.suites[0])

    def export_default(self, out_dir):
        export_to_csv(self.payload, out_dir)
        export_to_json(self.payload, out_dir)

    def export_filter(self, kv, out_dir):
        filtered_payload = filter_kv(self.payload, kv)
        export_to_csv(filtered_payload, out_dir)
        export_to_json(filtered_payload, out_dir)
        export_to_txt(filtered_payload, out_dir)

    def set_outputs(self, args):
        if args.output:
            self.output_file = args.output

        if args.output_dir:
            self.output_dir = args.output_dir

        if args.output_types:
            self.output_types = args.output_types

#
# compare
#
def run_test_compare(args):
    tests = args.compare.split(',')
    if len(tests) != 2:
        logging.info("It's allowed only to compare two lists")
        sys.exit(1)

    test1 = tests[0].split('=')
    if len(test1) != 2:
        logging.info("first test has incorrect format: test_name=test_file")
        sys.exit(1)

    test2 = tests[1].split('=')
    if len(test2) != 2:
        logging.info("second test has incorrect format: test_name=test_file")
        sys.exit(1)

    with open(test1[1], 'r') as f:
        test1_list = f.read().split('\n')

    with open(test2[1], 'r') as f:
        test2_list = f.read().split('\n')

    print(f"t1 name: {test1[0]}")
    print(f"t2 name: {test2[0]}")
    print(f"Total t1: {len(test1_list)}")
    print(f"Total t2: {len(test2_list)}")
    t1_not_t2 = list()
    t2_not_t1 = list()

    for t1 in test1_list:
        if t1 not in test2_list:
            t1_not_t2.append(t1)


    for t2 in test2_list:
        if t2 not in test1_list:
            t2_not_t1.append(t2)

    print(f"Total t1 not in t2: {len(t1_not_t2)}")
    print(f"Total t2 not in t1: {len(t2_not_t1)}")

#
# main
#
def main():
    parser = argparse.ArgumentParser(description='OpenShift Partner Certification Tool - Tests parser.')

    parser.add_argument('--filter-suites', dest='filter_suites',
                        default="openshift/conformance,kubernetes/conformance",
                        help='openshift-tests suite to run the filter, sepparated by comma.')
    parser.add_argument('--filter-key', dest='filter_k',
                        help='filter by key')
    parser.add_argument('--filter-value', dest='filter_v',
                        help='filter value of key')
    parser.add_argument('--output', dest='output',
                        help='output file path to save the results')
    parser.add_argument('--output-dir', dest='output_dir',
                        default="./tmp",
                        help='output file path to save the results')
    parser.add_argument('--output-types', dest='output_types',
                        default="json,csv,txt",
                        help='output types to export')

    parser.add_argument('--compare-tests-files', dest='compare',
                        default="",
                        help='Compare test files: aws-parallel=aws-parallel.txt,none-parallel=none-parallel.txt')


    args = parser.parse_args()

    if args.compare != "":
        return run_test_compare(args)

    texporter = TestsExporter()
    texporter.set_outputs(args)

    if not(args.filter_suites):
        # discovery suites by default:
        texporter.suites = ["openshift/conformance", "kubernetes/conformance"]
    else:
        texporter.suites = args.filter_suites.split(',')

    # Collect tests
    texporter.gather_tests()

    if args.filter_k:
        texporter.export_filter((args.filter_k, args.filter_v), args.output_dir)
        sys.exit(0)

    texporter.export_default(args.output_dir)
    sys.exit(0)

if __name__ == "__main__":
    main()
