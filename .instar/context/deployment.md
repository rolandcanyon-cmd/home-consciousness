# Deployment Guide

<!-- Customize this for your project's deployment setup. -->

## Pre-Deployment Checklist

1. Run coherence check: POST /coherence/check with action "deploy"
2. Verify you're in the correct project directory
3. Verify the deployment target matches the current topic/project
4. Run tests
5. Check CI status: GET /ci

## Deployment Targets

<!-- List your deployment targets here, e.g.:
- Production: https://myapp.vercel.app (Vercel)
- Staging: https://staging.myapp.com
-->

Check project map for auto-detected targets: GET /project-map

## Rollback Procedure

<!-- Document how to rollback if a deployment goes wrong -->

## Environment Variables

<!-- List required environment variables and where they're configured -->
