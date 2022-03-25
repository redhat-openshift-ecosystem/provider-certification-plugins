#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OpenShift tests discovery
    Discovery e2e tests for each suite, parse, classify
    and export to json.
    """
import sys
import json
import csv
import re
import argparse
import subprocess
#from this import d


bin_openshift_tests="tmp/origin/openshift-tests"
base_output_file="openshift-e2e-suites"
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


#
# Exporters
#
def export_to_csv(payload, odir):
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

    print(f"Json file saved in {odir}/{base_output_file}.csv")


def export_to_json(payload, odir):
    with open(f'{odir}/{base_output_file}.json', 'w') as outfile:
        json.dump(payload, outfile)
    print(f"Json file saved in {odir}/{base_output_file}.json")

#
# Exporter entity
#
class TestsExporter(object):
    suites = []
    payload = {
        "suites": []
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

#
# main
#
def main():
    payload = {
        "suites": []
    }

    parser = argparse.ArgumentParser(description='OpenShift Partner Certification Tool - Tests parser.')
    # parser.add_argument('integers', metavar='N', type=int, nargs='+',
    #                     help='an integer for the accumulator')
    # parser.add_argument('--output', dest='output', action='store_const',
    #                     const=sum, default=max,
    #                     help='sum the integers (default: find the max)')

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
    
    args = parser.parse_args()
    texporter = TestsExporter()

    if not(args.filter_suites):
        # discovery suites by default:
        texporter.suites = ["openshift/conformance", "kubernetes/conformance"]
    else:
        texporter.suites = args.filter_suites.split(',')

    # Collect tests
    texporter.gather_tests()

    if not(args.filter_k):
        texporter.export_default(args.output_dir)
        sys.exit(0)


if __name__ == "__main__":
    main()
