#!/usr/bin/env bash
docker-compose run --rm terraform init && docker-compose run --rm deploy
