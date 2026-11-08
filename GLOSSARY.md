# Home media server

The language used to describe the media library and its operation.

## Language

**Media library**: The organized collection available for playback or reading.
_Avoid_: Download folder

**Download staging**: Files being acquired or waiting to be imported into the
media library. _Avoid_: Media library

**Library manager**: An application that tracks wanted titles and imports
acquired files into a library. _Avoid_: Player

**Indexer manager**: An application that searches discovery providers and shares
their configuration with library managers.

**Request portal**: The place where viewers discover titles and request
additions to a library.

**Confined workload**: An application whose outbound network traffic must use a
designated VPN. _Avoid_: Anonymous application

**Recovery copy**: A copy from which important data can be restored after loss
of its original storage device. _Avoid_: Another directory on the same disk
