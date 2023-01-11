import winlean
import dynlib
import os


type
  WINTUN_ADAPTER_HANDLE* = distinct pointer
  WINTUN_SESSION_HANDLE* = distinct pointer
  WINTUN_LOGGER_CALLBACK* = proc(Level: WINTUN_LOGGER_LEVEL, Timestamp: int64, Message: ptr UncheckedArray[Utf16Char]) {.noconv.}
  WINTUN_LOGGER_LEVEL* = distinct cint

  WINTUN_CREATE_ADAPTER_FUNC* = proc(Name: WideCString, TunnelType: WideCString, RequestedGUID: ptr GUID): WINTUN_ADAPTER_HANDLE {.noconv, gcsafe.}
  WINTUN_OPEN_ADAPTER_FUNC* = proc(Name: WideCString): WINTUN_ADAPTER_HANDLE {.noconv, gcsafe.}
  WINTUN_CLOSE_ADAPTER_FUNC* = proc(Adapter: WINTUN_ADAPTER_HANDLE) {.noconv, gcsafe.}
  WINTUN_DELETE_DRIVER_FUNC* = proc(): cint {.noconv, gcsafe.}
  WINTUN_GET_ADAPTER_LUID_FUNC* = proc(Adapter: WINTUN_ADAPTER_HANDLE, Luid: ptr uint64) {.noconv, gcsafe.}
  WINTUN_GET_RUNNING_DRIVER_VERSION_FUNC* = proc(): int32 {.noconv, gcsafe.}
  WINTUN_SET_LOGGER_FUNC* = proc(NewLogger: WINTUN_LOGGER_CALLBACK) {.noconv, gcsafe.}
  WINTUN_START_SESSION_FUNC* = proc(Adapter: WINTUN_ADAPTER_HANDLE, Capacity: int32): WINTUN_SESSION_HANDLE {.noconv, gcsafe.}
  WINTUN_END_SESSION_FUNC* = proc(Session: WINTUN_SESSION_HANDLE) {.noconv, gcsafe.}
  WINTUN_GET_READ_WAIT_EVENT_FUNC* = proc(Session: WINTUN_SESSION_HANDLE): Handle {.noconv, gcsafe.}
  WINTUN_RECEIVE_PACKET_FUNC* = proc(Session: WINTUN_SESSION_HANDLE, PacketSize: ptr int32): ptr UncheckedArray[byte] {.noconv, gcsafe.}
  WINTUN_RELEASE_RECEIVE_PACKET_FUNC* = proc(Session: WINTUN_SESSION_HANDLE, Packet: ptr UncheckedArray[byte]) {.noconv, gcsafe.}
  WINTUN_ALLOCATE_SEND_PACKET_FUNC* = proc(Session: WINTUN_SESSION_HANDLE, PacketSize: int32): ptr UncheckedArray[byte] {.noconv, gcsafe.}
  WINTUN_SEND_PACKET_FUNC* = proc(Session: WINTUN_SESSION_HANDLE, Packet: ptr UncheckedArray[byte]) {.noconv, gcsafe.}

const
  WINTUN_MIN_RING_CAPACITY* = 0x20000  ## 128kiB
  WINTUN_MAX_RING_CAPACITY* = 0x4000000  ## 64MiB
  WINTUN_MAX_IP_PACKET_SIZE* = 0xFFFF

  WINTUN_LOG_INFO* = 0.WINTUN_LOGGER_LEVEL
  WINTUN_LOG_WARN* = 1.WINTUN_LOGGER_LEVEL
  WINTUN_LOG_ERR* = 2.WINTUN_LOGGER_LEVEL

var
  WintunCreateAdapter*: WINTUN_CREATE_ADAPTER_FUNC
  WintunOpenAdapter*: WINTUN_OPEN_ADAPTER_FUNC
  WintunCloseAdapter*: WINTUN_CLOSE_ADAPTER_FUNC
  WintunDeleteDriver*: WINTUN_DELETE_DRIVER_FUNC
  WintunGetAdapterLUID*: WINTUN_GET_ADAPTER_LUID_FUNC
  WintunGetRunningDriverVersion*: WINTUN_GET_RUNNING_DRIVER_VERSION_FUNC
  WintunSetLogger*: WINTUN_SET_LOGGER_FUNC
  WintunStartSession*: WINTUN_START_SESSION_FUNC
  WintunEndSession*: WINTUN_END_SESSION_FUNC
  WintunGetReadWaitEvent*: WINTUN_GET_READ_WAIT_EVENT_FUNC
  WintunReceivePacket*: WINTUN_RECEIVE_PACKET_FUNC
  WintunReleaseReceivePacket*: WINTUN_RELEASE_RECEIVE_PACKET_FUNC
  WintunAllocateSendPacket*: WINTUN_ALLOCATE_SEND_PACKET_FUNC
  WintunSendPacket*: WINTUN_SEND_PACKET_FUNC
  WintunLoaded*: bool = false  ## Set to true once initWintun was called once

proc `==`*(a, b: WINTUN_ADAPTER_HANDLE): bool {.borrow.}

proc `==`*(a, b: WINTUN_SESSION_HANDLE): bool {.borrow.}

proc `==`*(a, b: WINTUN_LOGGER_LEVEL): bool {.borrow.}
proc `<`*(a, b: WINTUN_LOGGER_LEVEL): bool {.borrow.}
proc `<=`*(a, b: WINTUN_LOGGER_LEVEL): bool {.borrow.}


template loadFunc(funcName: untyped, funcType: type): untyped =
  funcName = cast[funcType](lib.symAddr(astToStr(funcName)))
  if funcName == nil:
    raiseOSError(osLastError(), "Error loading dynamic symbol " & astToStr(funcName))

proc initWintun*() =
  ## Loads the dynamic symbols from wintun.dll. Does not need to be called
  ## explicitly when using the high-level wrapper.
  if WintunLoaded:
    return
  let lib = loadLib("wintun.dll")
  if lib == nil:
    raiseOSError(osLastError(), "Error opening wintun.dll")
  loadFunc(WintunCreateAdapter, WINTUN_CREATE_ADAPTER_FUNC)
  loadFunc(WintunOpenAdapter, WINTUN_OPEN_ADAPTER_FUNC)
  loadFunc(WintunCloseAdapter, WINTUN_CLOSE_ADAPTER_FUNC)
  loadFunc(WintunDeleteDriver, WINTUN_DELETE_DRIVER_FUNC)
  loadFunc(WintunGetAdapterLUID, WINTUN_GET_ADAPTER_LUID_FUNC)
  loadFunc(WintunGetRunningDriverVersion, WINTUN_GET_RUNNING_DRIVER_VERSION_FUNC)
  loadFunc(WintunSetLogger, WINTUN_SET_LOGGER_FUNC)
  loadFunc(WintunStartSession, WINTUN_START_SESSION_FUNC)
  loadFunc(WintunEndSession, WINTUN_END_SESSION_FUNC)
  loadFunc(WintunGetReadWaitEvent, WINTUN_GET_READ_WAIT_EVENT_FUNC)
  loadFunc(WintunReceivePacket, WINTUN_RECEIVE_PACKET_FUNC)
  loadFunc(WintunReleaseReceivePacket, WINTUN_RELEASE_RECEIVE_PACKET_FUNC)
  loadFunc(WintunAllocateSendPacket, WINTUN_ALLOCATE_SEND_PACKET_FUNC)
  loadFunc(WintunSendPacket, WINTUN_SEND_PACKET_FUNC)
  WintunLoaded = true
