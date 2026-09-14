"""Reconcile Sonarr, Radarr, Lidarr and Prowlarr resources."""

from common import ConfigurationError, merge


def resolve_arr_lookups(client, prefix, value, planned=None, dependencies=None):
    if isinstance(value, dict):
        if "_lookup" in value:
            spec = value["_lookup"]
            if set(value) != {"_lookup"} or set(spec) != {"endpoint", "name"}:
                raise ConfigurationError("Invalid named resource lookup")
            if spec["endpoint"] not in {"qualityprofile", "metadataprofile", "tag"}:
                raise ConfigurationError("Unsupported named resource lookup")
            candidates = client.request("GET", prefix + spec["endpoint"])
            key = "label" if spec["endpoint"] == "tag" else "name"
            matches = [item for item in candidates if item.get(key) == spec["name"]]
            if len(matches) != 1:
                dependency = {"endpoint": spec["endpoint"], "name": spec["name"]}
                if (
                    not matches
                    and planned is not None
                    and (spec["endpoint"], spec["name"]) in planned
                ):
                    if dependencies is not None and dependency not in dependencies:
                        dependencies.append(dependency)
                    return {"_plannedLookup": dependency}
                raise ConfigurationError("Named resource is missing or ambiguous")
            return matches[0]["id"]
        return {
            key: resolve_arr_lookups(client, prefix, item, planned, dependencies)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [
            resolve_arr_lookups(client, prefix, item, planned, dependencies)
            for item in value
        ]
    return value


def reconcile_arr(client, config, dry_run):
    version = "v1" if config["kind"] in {"lidarr", "prowlarr"} else "v3"
    prefix = f"/api/{version}/"
    counts = {"created": 0, "updated": 0, "unchanged": 0}
    allowed = {
        "rootfolder",
        "downloadclient",
        "indexer",
        "indexerproxy",
        "applications",
        "tag",
        "qualityprofile",
        "delayprofile",
        "notification",
        "remotepathmapping",
    }
    planned = set()
    dependencies = []
    settings = config.get("settings", {})
    media_fields = {
        "recycleBin": str,
        "recycleBinCleanupDays": int,
        "downloadPropersAndRepacks": str,
        "deleteEmptyFolders": bool,
        "fileDate": str,
        "rescanAfterRefresh": str,
        "setPermissionsLinux": bool,
        "chmodFolder": str,
        "chownGroup": str,
        "skipFreeSpaceCheckWhenImporting": bool,
        "minimumFreeSpaceWhenImporting": int,
        "copyUsingHardlinks": bool,
        "useScriptImport": bool,
        "scriptImportPath": str,
        "importExtraFiles": bool,
        "extraFileExtensions": str,
        "enableMediaInfo": bool,
    }
    media_fields.update(
        {
            "sonarr": {
                "autoUnmonitorPreviouslyDownloadedEpisodes": bool,
                "createEmptySeriesFolders": bool,
                "episodeTitleRequired": str,
            },
            "radarr": {
                "autoUnmonitorPreviouslyDownloadedMovies": bool,
                "createEmptyMovieFolders": bool,
                "autoRenameFolders": bool,
                "pathsDefaultStatic": bool,
            },
            "lidarr": {
                "autoUnmonitorPreviouslyDownloadedTracks": bool,
                "createEmptyArtistFolders": bool,
                "watchLibraryForChanges": bool,
                "allowFingerprinting": str,
            },
        }.get(config["kind"], {})
    )
    naming_fields = {
        "sonarr": {
            "renameEpisodes": bool,
            "replaceIllegalCharacters": bool,
            "colonReplacementFormat": int,
            "customColonReplacementFormat": str,
            "multiEpisodeStyle": int,
            "standardEpisodeFormat": str,
            "dailyEpisodeFormat": str,
            "animeEpisodeFormat": str,
            "seriesFolderFormat": str,
            "seasonFolderFormat": str,
            "specialsFolderFormat": str,
        },
        "radarr": {
            "renameMovies": bool,
            "replaceIllegalCharacters": bool,
            "colonReplacementFormat": int,
            "standardMovieFormat": str,
            "movieFolderFormat": str,
        },
        "lidarr": {
            "renameTracks": bool,
            "replaceIllegalCharacters": bool,
            "colonReplacementFormat": int,
            "standardTrackFormat": str,
            "multiDiscTrackFormat": str,
            "artistFolderFormat": str,
        },
    }.get(config["kind"], {})
    allowed_values = {
        "downloadPropersAndRepacks": {
            "preferAndUpgrade",
            "doNotUpgrade",
            "doNotPrefer",
        },
        "rescanAfterRefresh": {"always", "afterManual", "never"},
        "fileDate": {
            "none",
            "cinemas",
            "physicalRelease",
            "digitalRelease",
            "release",
            "localAirDate",
            "utcAirDate",
        },
        "episodeTitleRequired": {"always", "bulkSeasonReleases", "never"},
        "allowFingerprinting": {"allFiles", "newFiles", "never"},
    }
    policies = {
        "downloadHandling": (
            "downloadclient",
            {
                "enableCompletedDownloadHandling": bool,
                "autoRedownloadFailed": bool,
                "autoRedownloadFailedFromInteractiveSearch": bool,
            },
        ),
        "mediaManagement": ("mediamanagement", media_fields),
        "naming": ("naming", naming_fields),
    }
    if set(settings) - policies.keys():
        raise ConfigurationError("Unsupported manager settings section")
    for section, (endpoint_name, fields) in policies.items():
        declared = settings.get(section, {})
        if not declared:
            continue
        if (
            config["kind"] == "prowlarr"
            or set(declared) - fields.keys()
            or any(type(value) is not fields[name] for name, value in declared.items())
        ):
            raise ConfigurationError("Unsupported manager import policy")
        if any(
            isinstance(value, int) and not isinstance(value, bool) and value < 0
            for value in declared.values()
        ):
            raise ConfigurationError("Manager policy numbers cannot be negative")
        if any(
            name in allowed_values and value not in allowed_values[name]
            for name, value in declared.items()
        ):
            raise ConfigurationError("Unsupported manager policy value")
        if section == "naming" and any(
            fields[name] is str
            and name != "customColonReplacementFormat"
            and not value.strip()
            for name, value in declared.items()
        ):
            raise ConfigurationError("Manager naming formats cannot be empty")
        endpoint = prefix + "config/" + endpoint_name
        current = client.request("GET", endpoint)
        if not isinstance(current, dict) or set(declared) - current.keys():
            raise ConfigurationError("Manager does not expose declared import settings")
        desired = merge(current, declared)
        if config["mode"] == "bootstrap" or desired == current:
            counts["unchanged"] += 1
        else:
            counts["updated"] += 1
            if not dry_run:
                client.request("PUT", endpoint, desired)
    for resource in config.get("resources", []):
        endpoint = resource["endpoint"]
        if endpoint not in allowed:
            raise ConfigurationError("Unsupported resource endpoint")
        if endpoint == "indexerproxy" and config["kind"] != "prowlarr":
            raise ConfigurationError("Indexer proxies are only supported by Prowlarr")
        match = resource["match"]
        if not match or not set(match).issubset({"name", "path", "label"}):
            raise ConfigurationError("A stable name, path or label is required")
        values = resolve_arr_lookups(
            client,
            prefix,
            merge(resource.get("values", {}), match),
            planned if dry_run else None,
            dependencies,
        )
        objects = client.request("GET", prefix + endpoint)
        candidates = [
            obj for obj in objects if all(obj.get(k) == v for k, v in match.items())
        ]
        if len(candidates) > 1:
            raise ConfigurationError("Ambiguous resource identity")
        current = candidates[0] if candidates else None
        if current and config["mode"] == "bootstrap":
            counts["unchanged"] += 1
            continue
        if (
            current
            and "implementation" in values
            and current.get("implementation") != values["implementation"]
        ):
            raise ConfigurationError(
                "Existing provider implementation cannot be replaced"
            )
        template = current or {}
        if not current and "implementation" in values:
            schemas = client.request("GET", prefix + endpoint + "/schema")
            candidates = [
                schema
                for schema in schemas
                if schema.get("implementation") == values["implementation"]
            ]
            if len(candidates) != 1:
                raise ConfigurationError("Provider schema is missing or ambiguous")
            template = candidates[0]
        desired = merge(template, values)
        if current == desired:
            counts["unchanged"] += 1
        elif current:
            counts["updated"] += 1
            if not dry_run:
                client.request(
                    "PUT", prefix + endpoint + "/" + str(current["id"]), desired
                )
        else:
            counts["created"] += 1
            desired.pop("id", None)
            if not dry_run:
                client.request("POST", prefix + endpoint, desired)
            else:
                identity = match.get("name", match.get("label"))
                if identity is not None:
                    planned.add((endpoint, identity))
    if dependencies:
        counts["plannedDependencies"] = dependencies
    return counts
