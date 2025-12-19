#!/usr/bin/env bash

# Create the topic
rpk topic create weather

# Register the schema
rpk registry schema create weather-value --schema weather.avro --type avro