#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OpenShift tests discovery
    Discovery e2e tests for each suite, parse, classify
    and export to json.
    """
import sys
import json
import re
import subprocess

base_output_file="openshift-e2e-suites"


def parser_suite_tests(tests):
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
            "sig": '',
            "is_conformance": False
        }
        name = test_name

        # extract tags ('[<any char>]') from test name
        m_tags = re.findall(r'\[(.*?)\]+', test_name)
        for tag in m_tags:
            # discovery name: remove 'tags'
            name = name.replace(f"[{tag}]", "")

            # create flags from tags
            if tag.startswith('sig-'):
                test['sig'] = tag

            if tag == 'Conformance':
                test['is_conformance'] = True

            # set empty keys
            t = tag.split(':')
            if len(t) == 1:
                test['tags'].append({t[0]: ''})
                continue

            # ToDo: tag could be a tuple
            test['tags'].append({t[0]: ' '.join(t[1:])})

        # Save the parsed name (without tags)
        test['name_parsed'] = name.strip('"').strip()

        parsed_tests.append(test)

    return parsed_tests


def to_tags_str(tags):
    """
    Build inline tags as original: [key(|:value)]
    """
    tags_str = ""
    for t in tags:
        for key in t:
            if t[key] == '':
                tags_str+=(f"[{key}] ")
                continue
            tags_str+=(f"[{key}:{t[key]}] ")
    return tags_str


def export_to_csv(payload):
    import csv

    with open(f'{base_output_file}.csv', 'w', newline='') as csvfile:
        fieldnames = ['suite', 'sig', 'is_conformance', 'name_alias', 'tags', 'name']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames, delimiter=';')

        writer.writeheader()
        for suite in payload['suites']:
            for test in suite['tests']:
                writer.writerow({
                    'suite': suite['name'],
                    'sig': test['sig'],
                    'is_conformance': test['is_conformance'],
                    'name_alias': test['name_parsed'],
                    'tags': to_tags_str(test['tags']),
                    'name': test['name']
                })
    print("Json file saved in {base_output_file}.csv")


def export_to_json(payload):
    with open(f'{base_output_file}.json', 'w') as outfile:
        json.dump(payload, outfile)
    print("Json file saved in {base_output_file}.json")


def gather_suite_tests(suite):
    try:
        resp = subprocess.check_output(f"tmp/origin/openshift-tests run --dry-run {suite}", shell=True)
        return resp.decode("utf-8").split('\n')
    except subprocess.CalledProcessError as e:
        if e.returncode == 127:
            print("Please make sure the 'openshift-tests' binary exists")
            print("Did you build it by running ./build.sh script?")
        else:
            print(f"One or more error was found when collecting the list of tests for suite [{suite}]")
            print(f"Make sure you are able to run this command: {e.cmd}")
        sys.exit(e.returncode)


def main():
    payload = {
        "suites": []
    }

    # discovery tests for suite
    suites = ["openshift/conformance", "kubernetes/conformance"]
    
    for suite_name in suites:
        tests = gather_suite_tests(suite_name)
        parsed_tests = parser_suite_tests(tests)
        payload["suites"].append({
            "name": suite_name,
            "tests": parsed_tests
        })

    export_to_csv(payload)
    export_to_json(payload)
    #print(json.dumps(payload))


if __name__ == "__main__":
    main()
