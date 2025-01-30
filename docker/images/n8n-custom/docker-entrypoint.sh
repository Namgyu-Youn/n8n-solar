#!/bin/sh

if [ -d ".n8n" ]; then
	chmod o+rx -R .n8n
fi

tini -- n8n "$@"
