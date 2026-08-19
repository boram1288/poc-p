# SPDX-License-Identifier: MIT

.PHONY: fixture verify

fixture:
	./prepare-fixture.sh

verify:
	../../../../work/build/vision-pipeline/venv/bin/python verify_fixture.py \
		../../../../work/build/vision-pipeline/fixtures
