import winlean
import logging
import times
import os

import loader
export loader


type
  WintunAdapter* = WINTUN_ADAPTER_HANDLE  ## \
  ## Wintun adapter handle, alias for the low-level type.

  WintunSession* = WINTUN_SESSION_HANDLE  ## \
  ## Wintun session handle, alias for the low-level type.

  LoggerCallback* = proc(level: logging.Level, timestamp: Time, message: string)  ## \
  ## Logger callback type for the high-level wrapper with native Nim types.

  PacketBuffer* = tuple[data: ptr UncheckedArray[byte], len: int]  ## \
  ## Simple array pointer and lenght tuple, used for receiving and sending
  ## packets without memory copies.

proc createAdapter*(name: string, tunnelType: string, requestedGuid: GUID): WintunAdapter =
  ## Creates a Wintun adapter.
  ##
  ## https://git.zx2c4.com/wintun/about/#wintuncreateadapter
  initWintun()
  let adapterName = newWideCString(name)
  let adapterType = newWideCString(tunnelType)
  result = WintunCreateAdapter(adapterName, adapterType, requestedGuid.unsafeAddr)
  if result == nil:
    raiseOSError(osLastError(), "Failed to create TUN adapter " & name)

proc openAdapter*(name: string): WintunAdapter =
  ## Opens a Wintun adapter.
  ##
  ## https://git.zx2c4.com/wintun/about/#wintunopenadapter
  initWintun()
  let adapterName = newWideCString(name)
  result = WintunOpenAdapter(adapterName)
  if result == nil:
    raiseOSError(osLastError(), "Failed to open TUN adapter " & name)

proc close*(adapter: WintunAdapter) =
  ## Closes a Wintun adapter.
  ##
  ## https://git.zx2c4.com/wintun/about/#wintuncloseadapter
  WintunCloseAdapter(adapter)

proc deleteDriver*() =
  ## Deletes the driver instance.
  ##
  ## https://git.zx2c4.com/wintun/about/#wintundeletedriver
  initWintun()
  let success = WintunDeleteDriver()
  if success == 0:
    raiseOSError(osLastError(), "Failed to delete Wintun driver")

proc getLuid*(adapter: WintunAdapter): uint64 =
  ## Gets the LUID of an Adapter.
  ##
  ## https://git.zx2c4.com/wintun/about/#wintungetadapterluid
  WintunGetAdapterLUID(adapter, result.addr)

proc getRunningDriverVersion*(): int =
  ## Gets the currently runnign driver version.
  ##
  ## https://git.zx2c4.com/wintun/about/#wintungetrunningdriverversion
  initWintun()
  result = WintunGetRunningDriverVersion().int
  if result == 0:
    raiseOSError(osLastError(), "Failed to get Wintun version number")

var loggerCb: LoggerCallback = nil
proc loggerShim(level: WINTUN_LOGGER_LEVEL, timestamp: int64, message: ptr UncheckedArray[Utf16Char]) {.noconv.} =
  var nimLevel: logging.Level
  case level:
    of WINTUN_LOG_INFO: nimLevel = lvlInfo
    of WINTUN_LOG_WARN: nimLevel = lvlWarn
    of WINTUN_LOG_ERR: nimLevel = lvlError
    else: nimLevel = lvlInfo

  let nimTime = times.fromWinTime(timestamp)

  var strLen = 0
  while int16(message[strLen]) != 0:
    strLen += 1
  var messageWide = newWideCString(strLen)
  copyMem(messageWide[0].addr, message, strLen * 2 + 2)
  let nimMessage = $messageWide
  loggerCb(nimLevel, nimTime, nimMessage)

proc setLogger*(callback: LoggerCallback) =
  ## Sets the logger callback. Uses a shim procedure to translate the Windows
  ## API types to native Nim types.
  ##
  ## https://git.zx2c4.com/wintun/about/#wintunsetlogger
  initWintun()
  loggerCb = callback
  WintunSetLogger(loggerShim)

proc startSession*(adapter: WintunAdapter, capacity: int32): WintunSession =
  ## Starts a Wintun session.
  ##
  ## https://git.zx2c4.com/wintun/about/#wintunstartsession
  result = WintunStartSession(adapter, capacity)
  if result == nil:
    raiseOSError(osLastError(), "Failed to start Wintun Session")

proc close*(session: WintunSession) =
  ## Ends a Wintun session.
  ##
  ## https://git.zx2c4.com/wintun/about/#wintunendsession
  WintunEndSession(session)

proc getReadWaitEvent*(session: WintunSession): Handle =
  ## Gets Wintun session's read-wait event handle.
  ##
  ## https://git.zx2c4.com/wintun/about/#wintungetreadwaitevent
  result = WintunGetReadWaitEvent(session)

proc receivePacketUnchecked*(session: WintunSession): PacketBuffer =
  ## Receives a packet as a simple array pointer and lenght tuple that
  ## needs to be freed after use with
  ## `releaseReceivePacket <#releaseReceivePacket>`_. This version of
  ## `receivePacket` avoids copies by pointing to a driver allocated buffer.
  ## If the packet queue is exhausted the returned pointer is nil.
  ##
  ## https://git.zx2c4.com/wintun/about/#wintunreceivepacket
  var packetLen: int32
  result.data = WintunReceivePacket(session, packetLen.addr)
  result.len = packetLen
  if result.data == nil:
    let error = osLastError()
    if error != 259.OSErrorCode:  # Ignore ERROR_NO_MORE_ITEMS and return nil instead
      raiseOSError(error, "Failed to receive packet")

proc releaseReceivePacket*(session: WintunSession, packet: var PacketBuffer) =
  ## Release the internal buffer of a received packet.
  ##
  ## https://git.zx2c4.com/wintun/about/#wintunreleasereceivepacket
  WintunReleaseReceivePacket(session, packet.data)
  packet.data = nil
  packet.len = 0

proc receivePacketSeq*(session: WintunSession): seq[byte] =
  ## Receives a packet as a `seq[byte]`. Copies the received packet to the seq
  ## and immediately releases it. More convenient than the unchecked version
  ## if you need a seq anyway. If the packet queue is exhausted the returned seq is empty.
  var packetBuf = receivePacketUnchecked(session)
  if packetBuf.data != nil:
    result = newSeqUninitialized[byte](packetBuf.len)
    copyMem(result[0].addr, packetBuf.data, packetBuf.len)
    releaseReceivePacket(session, packetBuf)

proc receivePacketString*(session: WintunSession): string =
  ## Receives a packet as a `string`. Works the same way as
  ## `receivePacketSeq <#receivePacketSeq>`.
  var packetBuf = receivePacketUnchecked(session)
  if packetBuf.data != nil:
    result = newString(packetBuf.len)
    copyMem(result[0].addr, packetBuf.data, packetBuf.len)
    releaseReceivePacket(session, packetBuf)

proc allocateSendPacket*(session: WintunSession, packetSize: int): PacketBuffer =
  ## Allocates memory in the internal buffer to send a packet. It's
  ## automatically released when the packet is sent. Not needed when using the
  ## `string` and `seq[byte]` convenience procedures.
  ##
  ## https://git.zx2c4.com/wintun/about/#wintunallocatesendpacket
  result.len = packetSize
  result.data = WintunAllocateSendPacket(session, packetSize.int32)
  if result.data == nil:
    raiseOSError(osLastError(), "Failed to receive packet")

proc sendPacket*(session: WintunSession, packet: var PacketBuffer) =
  ## Sends a packet and releases the internal buffer.
  ##
  ## https://git.zx2c4.com/wintun/about/#wintunsendpacket
  WintunSendPacket(session, packet.data)
  packet.data = nil
  packet.len = 0

proc sendPacket*(session: WintunSession, packet: openarray[byte]) =
  ## Sends a packet contained in an array-like structure. Automatically
  ## manages the internal buffer.
  var packetBuf = session.allocateSendPacket(packet.len)
  copyMem(packetBuf.data, packet[0].unsafeAddr, packet.len)
  session.sendPacket(packetBuf)

proc sendPacket*(session: WintunSession, packet: string) =
  ## Sends a packet contained in a string. Automatically
  ## manages the internal buffer.
  var packetBuf = session.allocateSendPacket(packet.len)
  copyMem(packetBuf.data, packet[0].unsafeAddr, packet.len)
  session.sendPacket(packetBuf)
