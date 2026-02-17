.PHONY: docs

docs:
	swift package --allow-writing-to-directory ./docs \
		generate-documentation \
		--disable-indexing \
		--transform-for-static-hosting \
		--target AmoreLicensing \
		--output-path ./docs
		# --enable-experimental-combined-documentation \

docs-preview:
	swift package --disable-sandbox preview-documentation --target AmoreLicensing
