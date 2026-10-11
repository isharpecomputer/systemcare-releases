"""Uploads one release installer to Backblaze B2 and removes older versions of the same file."""
import os
import sys

from b2sdk.v2 import B2Api, InMemoryAccountInfo

local, b2_name, tag = sys.argv[1:4]

api = B2Api(InMemoryAccountInfo())
api.authorize_account("production", os.environ["B2_KEY_ID"], os.environ["B2_APP_KEY"])
bucket = api.get_bucket_by_name(os.environ["B2_BUCKET"])

fv = bucket.upload_local_file(local, b2_name, file_infos={"release_tag": tag})
folder = b2_name.rsplit("/", 1)[0]
for old, _ in bucket.ls(folder, latest_only=False):
    if old.file_name == b2_name and old.id_ != fv.id_:
        api.delete_file_version(old.id_, old.file_name)
print(f"Uploaded {b2_name} ({tag})")
