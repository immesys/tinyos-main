/**
 */

/**
 * NRF Spi interface
 */

#include "tinyos_ble.h"
#include "printf.h"

module NrfBleP
{
  provides interface BlePeripheral;
  provides interface BleCentral;
  provides interface BleLocalChar as BleLocalChar[uint8_t];
  provides interface NrfBleService as NrfBleService[uint8_t];
  uses interface HplSam4lUSART as SpiHPL;
  uses interface SpiPacket;
  uses interface GeneralIO as CS;
  uses interface GeneralIO as IntPort;
  uses interface GpioInterrupt as Int;
  uses interface Timer<T32khz> as tmr;
}
implementation
{

  #define SPI_PKT_LEN 50

  task void initSpi();

  uint8_t txbufs[10][SPI_PKT_LEN];
  int txbuf_hd = 0;
  int txbuf_tl = 0;
  uint8_t spibusy = 0;
  error_t enqueue_tx(uint8_t *req, uint8_t len) {
    bool doSpi = 0;
    atomic {
      if (len > SPI_PKT_LEN) {
        printf ("fail\n");
        return FAIL;  
      }

      if (txbuf_hd - txbuf_tl == 1 || txbuf_hd == 0 && txbuf_tl == 9) {
      printf ("fail\n");
        return FAIL;
      }

      memcpy(txbufs[txbuf_tl], req, len);
      txbuf_tl = (txbuf_tl + 1) % 10;
      //doSpi = txbuf_tl - txbuf_hd == 1 || txbuf_tl == 0 && txbuf_hd == 9;
    }


    //if (doSpi) {
      post initSpi();
   // } else {
   //   printf("no dospi\n");
   // }

    return SUCCESS;
  }

  uint8_t rxbuf[SPI_PKT_LEN];

  typedef struct
  {
    uuid_t UUID;
  } Char_t;

  Char_t chars[MAX_CHARS];

  void setCharUUID(uint8_t handle, uuid_t UUID) {
    chars[handle].UUID = UUID;
  }

  uuid_t getCharUUID(uint16_t handle) {
    return chars[handle].UUID;
  }

  command uint8_t BleLocalChar.getHandle[uint8_t handle]() {
    return handle;
  }

  command void BleLocalChar.setUUID[uint8_t handle](uuid_t UUID) {
    setCharUUID(handle, UUID);
  }

  command uuid_t BleLocalChar.getUUID[uint8_t handle]() {
    return getCharUUID(handle);
  }

  command error_t BleLocalChar.setValue[uint8_t handle](uint16_t len, uint8_t const *value){
    return SUCCESS;
  }

  command error_t BleLocalChar.getValue[uint8_t handle]() {
    return SUCCESS;
  }

  command error_t BleLocalChar.notify[uint8_t handle](uint16_t len,
    uint8_t const *value)
  {
    uint8_t txbuf[SPI_PKT_LEN];
    if (len > SPI_PKT_LEN - 2) {
      return FAIL;  
    }
    txbuf[0] = SPI_NOTIFY;
    txbuf[1] = handle;
    txbuf[2] = len;
    memcpy(txbuf + 3, value, len);
    return enqueue_tx(txbuf, len + 3);
  }

  command error_t BleLocalChar.indicate[uint8_t handle](uint16_t len, uint8_t const *value) {
    return SUCCESS;
  }

  command error_t NrfBleService.createService[uint8_t handle](uuid_t UUID) {
    uint8_t txbuf[4];
    txbuf[0] = SPI_ADD_SERVICE;
    txbuf[1] = handle;
    txbuf[2] = (uint8_t)UUID;
    txbuf[3] = (uint8_t)(UUID >> 8);
    return enqueue_tx(txbuf, sizeof(txbuf));
  }


  command error_t NrfBleService.addCharacteristic[uint8_t service_handle](uuid_t UUID, uint8_t char_handle)
  {
    uint8_t txbuf[5];
    txbuf[0] = SPI_ADD_CHARACTERISTIC;
    txbuf[1] = service_handle;
    txbuf[2] = char_handle;
    txbuf[3] = (uint8_t)UUID;
    txbuf[4] = (uint8_t)(UUID >> 8);
    return enqueue_tx(txbuf, sizeof(txbuf));
  }

  command error_t BleCentral.scan() {
    uint8_t txbuf[1];
    txbuf[0] = SPI_START_SCAN;
    return enqueue_tx(txbuf, sizeof(txbuf));
  }

  command error_t BlePeripheral.startAdvertising(uint8_t *data, uint8_t len) {
    uint8_t txbuf[33];
    if (len > 12) len = 12;
    txbuf[0] = SPI_START_ADVERTISING;
    txbuf[1] = len+16;
    //02 01 06 //flags
    txbuf[2] = 0x02; //flags
    txbuf[3] = 0x01;
    txbuf[4] = 0x06; //BLE only
    txbuf[5] = 0x0A;
    txbuf[6] = 0x09; //Device name
    txbuf[7] = 'F';
    txbuf[8] = 'i';
    txbuf[9] = 'r';
    txbuf[10] = 'e';
    txbuf[11] = 's';
    txbuf[12] = 't';
    txbuf[13] = 'o';
    txbuf[14] = 'r';
    txbuf[15] = 'm';
    txbuf[16] = len + 1;
    txbuf[17] = 0xFE; //Standards noncompliant extra data
    memcpy(txbuf+18, data, len);
    return enqueue_tx(txbuf, len+18);


    /*
    if (len > 20) len = 20;
    memcpy(&txbuf[2], data, len);
    txbuf[1] = len;

    return enqueue_tx(txbuf, len+2);
    */
  }

  command error_t BlePeripheral.stopAdvertising() {
    //TODO(alevy): implement nrf stop advertising over SPI
    return SUCCESS;
  }

  task void initialize()
  {
    uint8_t txbuf[1];
    txbuf[0] = SPI_RESET;
    call SpiHPL.enableUSARTPin(USART2_TX_PC12);
    call SpiHPL.enableUSARTPin(USART2_RX_PC11);
    call SpiHPL.enableUSARTPin(USART2_CLK_PA18);
    call SpiHPL.initSPIMaster();
    call SpiHPL.setSPIMode(0,0);
    call SpiHPL.setSPIBaudRate(1000000);
    call SpiHPL.enableTX();
    call SpiHPL.enableRX();

    call CS.makeOutput();
    call CS.set();
    call IntPort.makeInput();
    call Int.enableRisingEdge();

    enqueue_tx(txbuf, sizeof(txbuf));
  }

  async event void Int.fired()
  {
    uint8_t txbuf[1];
    txbuf[0] = SPI_NOOP;
    enqueue_tx(txbuf, sizeof(txbuf));
  }

  uint8_t initialized = 0;
  event void tmr.fired()
  {
    if (!initialized) {
        signal BlePeripheral.ready();
        signal BleCentral.ready();
        call tmr.startPeriodic(16000);
        initialized = 1;
    } else {
        uint8_t txbuf[1];
        txbuf[0] = SPI_NOOP;
        enqueue_tx(txbuf, sizeof(txbuf));
    }
  }
  command void BlePeripheral.initialize() {
    post initialize();
  }

  command void BleCentral.initialize() {
    //post initialize();
  }

  task void initSpi() {
    uint8_t *buf;
    if (spibusy) return;
    atomic {
      buf = txbufs[txbuf_hd];
      if (txbuf_hd == txbuf_tl) {
        return;
      }
      txbuf_hd = (txbuf_hd + 1) % 10;
    }
    call CS.clr();
    spibusy = 1;
    call SpiPacket.send(buf, rxbuf, SPI_PKT_LEN);
  }


  task void ready() {
    //After the RESET, the chip requires like a second to regain its senses
    call tmr.startOneShot(16000);
  }

  task void connected() {
    signal BlePeripheral.connected();
  }

  task void disconnected() {
    signal BlePeripheral.disconnected();
  }

  uint8_t writebuf [26];

  // Doesn't guarantee that all writes make it through
  // TODO better handoff
  task void write() {
    uint8_t copy [26];
    atomic {
        memcpy(copy, writebuf, 26);
    }
    signal BleLocalChar.onWrite[copy[0]]((uint16_t)copy[1], &copy[2]);
  }

  default event void BlePeripheral.ready() {}
  default event void BlePeripheral.connected() {}
  default event void BlePeripheral.disconnected() {}

  default event void BleLocalChar.onWrite[uint8_t id](uint16_t len, uint8_t const *value) {}
  default event void BleCentral.ready() {}
  default async event void BleCentral.advReceived(uint8_t* addr,
    uint8_t *data, uint8_t dlen, uint8_t rssi) {}

  async event void SpiPacket.sendDone(uint8_t* txBuf, uint8_t* rxBuf,
                                      uint16_t len, error_t error) {
    call CS.set();
    if (error == SUCCESS) {
      if (rxBuf[0] == 0xee) {
        printf("Retrying ble tx...\n");
        call CS.clr();
        call SpiPacket.send(txBuf, rxbuf, SPI_PKT_LEN);
        return;
      }
      spibusy=0;
      switch (rxBuf[0]) {
        case SPI_RESET:
          post ready();
          break;
        case SPI_CONNECT:
          post connected();
          break;
        case SPI_DISCONNECT:
          post disconnected();
          break;
        case SPI_ADVERTISE:
          signal BleCentral.advReceived(rxBuf + 1, rxBuf + 9, rxBuf[8], rxBuf[7]);
          break;
        case SPI_WRITE:
          signal BleLocalChar.onWrite[rxBuf[1]](rxBuf[2], &rxBuf[3]);
          break;
        case SPI_DEBUG:
          printf("[NRF] %s\n", rxBuf + 1);
          break;
      }
    }
    post initSpi();
  }
}
