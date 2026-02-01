# How to Request Movies & TV Shows

This guide explains how to add content to your media library.

## Quick Start: Using Jellyseerr

**Jellyseerr** is your Netflix-like interface for requesting content.

### Access Jellyseerr
- **Local**: http://server-ip:5055
- **Remote**: https://requests.yourdomain.com

### Request a Movie

1. Open Jellyseerr
2. Search for the movie you want (e.g., "Inception")
3. Click on the movie poster
4. Click **"Request"**
5. Done! The movie will be automatically:
   - Searched for by Radarr
   - Downloaded by qBittorrent (through VPN)
   - Moved to your media library
   - Available in Jellyfin within minutes to hours

### Request a TV Show

1. Open Jellyseerr
2. Search for the show (e.g., "Breaking Bad")
3. Click on the show poster
4. Choose what to request:
   - **All Seasons**: Entire series
   - **Specific Season**: Just one season
   - **Specific Episodes**: Individual episodes
5. Click **"Request"**
6. Sonarr will handle the rest automatically

### Request Status

- **Pending**: Waiting for approval (if enabled)
- **Approved**: Being searched/downloaded
- **Available**: Ready to watch in Jellyfin

---

## How the Automation Works

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Jellyseerr    │────▶│  Radarr/Sonarr  │────▶│    Prowlarr     │
│  (You request)  │     │ (Finds release) │     │ (Searches sites)│
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                         │
                                                         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    Jellyfin     │◀────│  Radarr/Sonarr  │◀────│   qBittorrent   │
│  (You watch!)   │     │(Imports & renames)    │ (Downloads/VPN) │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

### Step-by-Step Flow

1. **You request** "The Batman (2022)" in Jellyseerr
2. **Jellyseerr** sends request to Radarr
3. **Radarr** asks Prowlarr to search indexers
4. **Prowlarr** searches configured torrent/usenet sites
5. **Radarr** picks the best quality release (based on TRaSH profiles)
6. **qBittorrent** downloads through Mullvad VPN
7. **Radarr** moves, renames, and organizes the file
8. **Bazarr** downloads subtitles automatically
9. **Jellyfin** scans library and shows new content
10. **You watch** on Apple TV, iPhone, web, etc.

---

## Alternative Methods

### Method 2: Directly in Radarr/Sonarr

For power users who want more control:

**Radarr (Movies)** - http://server-ip:7878
1. Click "Add New"
2. Search for movie
3. Select quality profile
4. Click "Add Movie"
5. Click "Search" (magnifying glass icon)

**Sonarr (TV Shows)** - http://server-ip:8989
1. Click "Add New"
2. Search for show
3. Select quality profile
4. Enable "Season Monitoring"
5. Click "Add Series"
6. Click "Search Monitored" for existing episodes

### Method 3: Automatic Lists

You can sync external lists to automatically add content:

**IMDb Watchlist**
1. In Radarr: Settings → Import Lists → Add → IMDb Lists
2. Enter your IMDb list URL
3. New movies you add to IMDb will auto-download

**Trakt Lists**
1. In Sonarr: Settings → Import Lists → Add → Trakt
2. Authenticate with Trakt
3. Select lists to sync (Popular, Trending, Watchlist)

---

## Content Types & Apps

| Content Type | Management App | Request Via |
|--------------|----------------|-------------|
| Movies | Radarr | Jellyseerr |
| TV Shows | Sonarr | Jellyseerr |
| Music | Lidarr | Lidarr directly |
| Audiobooks | Readarr → Audiobookshelf | Readarr |
| Books/eBooks | Readarr | Readarr |
| Podcasts | Audiobookshelf | Audiobookshelf |

### Music (Lidarr)

1. Open Lidarr: http://server-ip:8686
2. Artist → Add New
3. Search for artist
4. Select albums to monitor
5. Click Add

### Audiobooks (Readarr + Audiobookshelf)

1. Open Readarr: http://server-ip:8787
2. Search for book/audiobook
3. Add and search
4. Audiobookshelf will automatically detect new audiobooks

---

## Quality Profiles Explained

**Recyclarr** syncs quality preferences from TRaSH Guides:

### Radarr Profiles
- **HD Bluray + WEB**: Best 1080p quality (Bluray preferred, WEB fallback)
- **UHD Bluray + WEB**: Best 4K quality

### Sonarr Profiles
- **WEB-1080p**: Best 1080p streaming releases
- **WEB-2160p**: Best 4K streaming releases

These ensure you get:
- ✓ Proper audio (original language, surround sound)
- ✓ High bitrate video
- ✓ No low-quality re-encodes
- ✓ Correct release groups

---

## Troubleshooting

### "No results found"

1. Check Prowlarr has indexers configured
2. Try searching in Prowlarr directly to verify
3. Some content may not be available yet

### "Download stuck"

1. Check qBittorrent: http://server-ip:8080
2. Verify VPN is connected: `docker exec gluetun curl https://am.i.mullvad.net/connected`
3. Check if ports are blocked by ISP

### "Movie downloaded but not in Jellyfin"

1. Check Radarr Activity tab for import status
2. Verify file permissions (PUID/PGID)
3. Trigger Jellyfin library scan: Settings → Libraries → Scan

### "Subtitles missing"

1. Check Bazarr: http://server-ip:6767
2. Verify subtitle providers are configured
3. Click "Search" on specific movie/episode

---

## Mobile Access

### iPhone/iPad
1. Download **Jellyfin** app from App Store
2. Enter server URL: http://server-ip:8096 (local) or https://jellyfin.yourdomain.com (remote)
3. Login with your Jellyfin account

### Apple TV
1. Download **Swiftfin** or **Infuse** from App Store
2. Add server with URL
3. Stream directly to TV

### Requesting on Mobile
1. Open Jellyseerr in Safari: http://server-ip:5055
2. Add to Home Screen for app-like experience
3. Search and request just like on desktop

---

## Pro Tips

### 1. Use Jellyseerr "Discover" Tab
Browse trending, popular, and recommended content. One-click request.

### 2. Set Up User Accounts
Create Jellyseerr accounts for family members. They can request, you approve.

### 3. Auto-approve Requests
In Jellyseerr settings, you can auto-approve requests for trusted users.

### 4. Monitor Progress
Check the Activity tabs in Radarr/Sonarr to see download progress.

### 5. Upgrade Existing Content
Radarr/Sonarr will automatically upgrade files if a better quality release becomes available.
