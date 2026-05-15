# Incubator OS

Internal operating system for The Incubator - admin tools and multi-tenant client dashboard.

## Overview

This repository contains tools organized by client:

**General Tools** (system-wide):
- **Admin Tools** (`/admin`) - Email drafting, sync management, SEO strategy, playbooks, user lookup
- **JARVIS Chat** (`/chat`) - AI assistant with voice/text
- **File Manager** (`/files`) - Secure file upload and management
- **System Settings** (`/settings`) - QuickBooks integration configuration

**Client-Specific Tools** (organized by folder):
- **Northport CPA** - Dashboard, clients, team settings
- **Priceless CPA** - Dashboard, clients, team settings
- **LSS** - Dashboard, clients, invoice reports, automations, legacy dashboard

**Cron Jobs** - Automated email sync, playbook alerts, and automation execution (daily at 7 AM EST)

## Development

```bash
# Install dependencies
npm install

# Run development server
npm run dev

# Build for production
npm run build

# Start production server
npm start
```

## Architecture

**Multi-Tenant:** All data scoped by `company_id`
**Database:** Shared Supabase instance with incubator-website
**Authentication:** Localhost bypass enabled by default (set `NEXT_PUBLIC_REQUIRE_AUTH_LOCAL=true` to test auth)

### Directory Structure

```
src/
├── app/
│   ├── admin/              # Admin tools
│   ├── dashboard/[team_id]/ # Multi-tenant dashboard
│   ├── api/
│   │   ├── _lib/           # Shared infrastructure (33 files)
│   │   ├── admin/          # Admin API routes
│   │   ├── team/[teamId]/  # Team API routes (auth required)
│   │   └── cron/           # Cron job endpoints
│   ├── components/         # Shared UI components
│   └── providers/          # Auth providers
└── lib/                    # Client-side utilities
```

## Environment Variables

See `.env.example` for complete list. Required variables:

```env
# Database
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=

# Azure/Microsoft (per team)
NORTHPORT_CPA_AZURE_CLIENT_ID=
NORTHPORT_CPA_AZURE_CLIENT_SECRET=
NORTHPORT_CPA_AZURE_TENANT_ID=

# ... (same for PRICELESS_CPA and LSS)

# AI Services
ANTHROPIC_API_KEY=
GOOGLE_GEMINI_API_KEY=

# External Integrations
NOTION_API_KEY=
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=

# Security
CRON_SECRET=
```

## Deployment

Deployed on Vercel with cron jobs configured in `vercel.json`:
- Email sync: Daily at 7 AM EST
- Playbook alerts: Daily at 7 AM EST
- Automation execution: Mon/Thu at 7 AM EST

## Key Features

### Admin Tools
- **Email Drafting**: AI-powered draft generation with Anthropic/Gemini
- **Email Sync**: Validate Microsoft Graph sync status
- **Playbooks**: Notion-based playbook management with automated alerts
- **SEO Strategy**: AI platform visibility tracking (ChatGPT, Claude, Perplexity, Google AI)

### Client Dashboard
- **Email Monitoring**: Unanswered emails, SLA tracking, team performance
- **SMS Monitoring**: Client communication tracking (Quo/Twilio)
- **Client Management**: Service assignments, notes, context aggregation
- **Team Settings**: Member management, service configuration

## Database Schema

All tables scoped by `company_id`:
- `client_list` - Client records
- `team_memberships` - User-to-team assignments
- `email_events` - Email tracking
- `sms_messages` - SMS tracking
- `service_assignments` - Service mappings

## Migration Notes

This repository was migrated from `incubator-website` on 2026-01-28. Both repos share the same Supabase database but are otherwise independent. See `MIGRATION.md` for details.

## License

Proprietary

