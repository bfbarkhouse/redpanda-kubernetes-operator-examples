#!/usr/bin/env bash

# Create the topic
rpk topic create events

# Register the schema
rpk registry schema create events-value --schema events.avro --type avro

# Produce encoded messages
rpk topic produce events --schema-id=topic

{"user_id":1337,"event_type":"BUTTON_CLICK","ts":"2025-12-15T00:00:00.000Z"}
{"user_id":1337,"event_type":"PAGE_VIEW","ts":"2025-12-15T00:20:00.000Z"}
{"user_id":1234,"event_type":"BUTTON_CLICK","ts":"2025-12-15T01:00:00.000Z"}
{"user_id":8888,"event_type":"ADD_TO_CART","ts":"2025-12-15T02:15:15.000Z"}
{"user_id":2324,"event_type":"BUTTON_CLICK","ts":"2025-12-15T03:35:01.000Z"}
{"user_id":1111,"event_type":"EXIT_PAGE","ts":"2025-12-15T06:012:15.000Z"}
