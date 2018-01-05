/*
 ============================================================================
 Name        : wm_refCodec_Dt00.c
 Author      : Andy Maginnis
 Version     : 1
 Copyright   : MIT (See below)
 Description : Reference for data format
 ============================================================================

 MIT License

 Copyright (c) 2017 Andy Maginnis

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.

 */

#include <stdio.h>
#include <stdlib.h>

#define READINGS_BUFFER_SIZE     30
#define BYTEBUFFERSIZE           1000 // Note this example has no byte overrun protection

#define WINDOPDATAPACKET_T3_TYPE 0x02
#define WINDOPDATAPACKET_T4_TYPE 0x03
#define WINDOPDATAPACKET_T5_TYPE 0x04
#define WINDOPDATAPACKET_T6_TYPE 0x06

//*****************************************************************************
//
//! \brief Used in the RTC_C_initCalendar() function as the CalendarTime
//! parameter. (TI Header)
//
//*****************************************************************************
typedef struct Calendar {
    //! Seconds of minute between 0-59
    uint8_t Seconds;
    //! Minutes of hour between 0-59
    uint8_t Minutes;
    //! Hour of day between 0-23
    uint8_t Hours;
    //! Day of week between 0-6
    uint8_t DayOfWeek;
    //! Day of month between 1-31
    uint8_t DayOfMonth;
    //! Month between 0-11
    uint8_t Month;
    //! Year between 0-4095
    uint16_t Year;
} Calendar;

/* ****************************************************************************
 *
 * Define struct of reading types
 *
 * */
typedef struct WindOpDataPacket_t3 {
    uint16_t ws; // Average minute windspeed
    uint16_t wsx; // Second max speed windspeed
    uint16_t wsm; // Second min windspeed
    uint16_t wd;  // Wind direction
    int16_t tmp; // temperature
    uint16_t press; // Pressure
    uint16_t hum; // Humidity
    uint16_t bv; // Battery Voltage
} WindOpDataPacket_t3;


/*
 * Optional data structs that can be used.
 *
 * */
typedef struct WindOpDataPacket_t4 {
    uint16_t ws; // Average minute windspeed
    uint16_t wsx; // Second max speed windspeed
    uint16_t wsm; // Second min windspeed
    uint16_t wd;  // Wind direction
} WindOpDataPacket_t4;

typedef struct WindOpDataPacket_t5 {
    int16_t tmp; // temperature
    uint16_t press; // Pressure
    uint16_t hum; // Humidity
    uint16_t bv; // Battery Voltage
} WindOpDataPacket_t5;

/* ****************************************************************************
 *
 * Packet packing control struct
 *
 * */
typedef struct packCtrl {
    Calendar time;
    uint8_t incSeconds;
    uint8_t numOfReadings;
    uint8_t extendedTimeFormat;
    uint8_t dataType;
    uint8_t packetLength;

    // Note as T3 & T4 are subsets we simple reuse the T2 structure.
    //
    WindOpDataPacket_t3 readings[READINGS_BUFFER_SIZE];

} packCtrl;

/* ****************************************************************************
 * Pretty print helper functions
 * */
void dump_breaker() {
    printf("*************************************************************\n");
}
void dump_StrWithBreaker(char * str) {
    dump_breaker();
    printf("** %s\n", str);
    dump_breaker();
}

void dump_WindOpDataReadings_t3(WindOpDataPacket_t3 * readingsIn) {
    printf("ws  %d\n", readingsIn->ws);
    printf("wsx %d\n", readingsIn->wsx);
    printf("wsx %d\n", readingsIn->wsm);
    printf("wd  %d\n", readingsIn->wd);
    printf("tmp %d\n", readingsIn->tmp);
    printf("prs %d\n", readingsIn->press);
    printf("hum %d\n", readingsIn->hum);
    printf("bv  %d\n", readingsIn->bv);
}

void dump_WindOpMinuteTime(Calendar * timeIn) {
    printf("Y %d\n", timeIn->Year);
    printf("M %d\n", timeIn->Month);
    printf("D %d\n", timeIn->DayOfMonth);
    printf("H %d\n", timeIn->Hours);
    printf("m %d\n", timeIn->Minutes);
    printf("S %d\n", timeIn->Seconds);
}

/* ****************************************************************************
 * Test helper functions
 * */
uint16_t testValue(char * str, uint16_t v1, uint16_t v2) {
    if (v1 != v2) {
        printf("%-20s %8x %8x  .... ERROR\n", str, v1, v2);
        return 1;
    } else {
        printf("%-20s %8d %8d  ....\n", str, v1, v2);
        return 0;
    }
}

uint16_t test_WindOpDataReadings(WindOpDataPacket_t3 * readingsIn1, WindOpDataPacket_t3 * readingsIn2, uint8_t dataType) {
    uint16_t error = 0;

    if ((dataType == WINDOPDATAPACKET_T3_TYPE) | (dataType == WINDOPDATAPACKET_T4_TYPE)) {

        error += testValue("ws ", readingsIn1->ws, readingsIn2->ws);
        error += testValue("wsx", readingsIn1->wsx, readingsIn2->wsx);
        error += testValue("wsx", readingsIn1->wsm, readingsIn2->wsm);
        error += testValue("wd ", readingsIn1->wd, readingsIn2->wd);
    }
    if ((dataType == WINDOPDATAPACKET_T3_TYPE) | (dataType == WINDOPDATAPACKET_T5_TYPE)) {
        error += testValue("tmp", readingsIn1->tmp, readingsIn2->tmp);
        error += testValue("prs", readingsIn1->press, readingsIn2->press);
        error += testValue("hum", readingsIn1->hum, readingsIn2->hum);
        error += testValue("bv ", readingsIn1->bv, readingsIn2->bv);
    }
    return error;
}

uint16_t test_WindOpMinuteTime(Calendar * timeIn1, Calendar * timeIn2) {
    uint16_t error = testValue("Y", timeIn1->Year, timeIn2->Year);
    error += testValue("M", timeIn1->Month, timeIn2->Month);
    error += testValue("D", timeIn1->DayOfMonth, timeIn2->DayOfMonth);
    error += testValue("H", timeIn1->Hours, timeIn2->Hours);
    error += testValue("m", timeIn1->Minutes, timeIn2->Minutes);
    error += testValue("S", timeIn1->Seconds, timeIn2->Seconds);
    return error;
}

/* ****************************************************************************
 * Set the time helper function
 * */
void setExampleTime(Calendar * timeStr, uint16_t yy, uint16_t mm, uint16_t dd, uint16_t hh, uint16_t min, uint16_t ss) {
    timeStr->Year = yy;
    timeStr->Month = mm;
    timeStr->DayOfMonth = dd;
    timeStr->Hours = hh;
    timeStr->Minutes = min;
    timeStr->Seconds = ss;
}

/* ****************************************************************************
 * Set data point helper function
 * */
void setdataPoint(WindOpDataPacket_t3 * data, uint16_t ws, uint16_t wsx, uint16_t wsm) {
    data->bv = 12034;
    data->hum = 0x551f;
    data->tmp = 0x1234;
    data->press = 0x0987;
    data->wd = 345;
    data->ws = ws;
    data->wsx = wsx;
    data->wsm = wsm;
}

/* ****************************************************************************
 * ****************************************************************************
 * ***              PACKING FUNCTIONS OF INTEREST START                 *******
 * ****************************************************************************
 * ****************************************************************************
 * */

/* ****************************************************************************
 *
 * Pack the time stamp. 4 & 5 Byte version
 *
 * EYYY_YYYY___YYYY_MMMM___DDDD_DHHH___HHmm_mmmm
 *
 * E     : If set use extended second format, addition byte containing seconds
 * Year  : 11 bits contain the year, 0...2047
 * Month :  4 bits contain the Month, 1...12
 * Day   :  5 bits contain the day of the Month 1...31
 * Hour  :  5 bits contain the hour 0...23
 * Minute:  6 bits contain the minute 0...59
 *
 * If Extended
 * Seconds: 6 bits contain the seconds 0...59
 * Year   : 2 bits added to the MSB of the Year, becomes 13 bits instead of 11.
 *          Am I being serious here? These could be used for something else.
 *
 * */
uint16_t pack_WindOpMinuteTime(Calendar * timeIn, uint8_t * outBuffer, uint8_t incSecs) {
    uint8_t working1;
    uint8_t working2;

    // Remember LSByte first
    // HHmm_mmmm
    working2 = (timeIn->Hours & 0x03) << 6;
    outBuffer[0] = timeIn->Minutes + working2;

    // DDDD_DHHH
    working2 = (timeIn->Hours & 0x1F) >> 2;
    working1 = (timeIn->DayOfMonth & 0x1F) << 3;
    outBuffer[1] = working1 + working2;

    // YYYY_MMMM
    working2 = (timeIn->Month & 0x0F);
    working1 = (timeIn->Year & 0x0F) << 4;
    outBuffer[2] = working1 + working2;

    // EYYY_YYYY
    working2 = ((timeIn->Year >> 4) & 0x7F);
    outBuffer[3] = working2;

    // Extended format, extra byte with seconds
    if (incSecs) {
        outBuffer[3] |= 0x80;
        outBuffer[4] = ((timeIn->Year & 0x1800) >> 5);
        outBuffer[4] += (timeIn->Seconds & 0x3F);
        return 5;
    } else {
        return 4;
    }

}

/* ****************************************************************************
 *
 * Reverse the PACK routine
 *
 * */
uint16_t unpack_WindOpMinuteTime(Calendar * timeIn, uint8_t * outBuffer) {

    // Remember LSByte first
    // HHmm_mmmm
    timeIn->Minutes = outBuffer[0] & 0x3F;
    timeIn->Hours = (outBuffer[0] & 0xC0) >> 6;

    // DDDD_DHHH
    timeIn->Hours += ((outBuffer[1] & 0x7) << 2);
    timeIn->DayOfMonth = (outBuffer[1] & 0xF8) >> 3;

    // YYYY_MMMM
    timeIn->Month = (outBuffer[2] & 0x0F);
    timeIn->Year = (outBuffer[2] & 0xF0) >> 4;

    // EYYY_YYYY
    timeIn->Year += (outBuffer[3] & 0x7F) << 4;

    if ((outBuffer[3] & 0x80) == 0x80) {
        timeIn->Year += (outBuffer[4] & 0xC0) << 5;
        timeIn->Seconds = outBuffer[4] & 0x3F;
        return 5;
    } else {
        return 4;
    }

}
/* ****************************************************************************
 *
 * Pack a data reading.
 *
 * */
uint16_t pack_WindOpDataReadings_t3(struct WindOpDataPacket_t3 * readingsIn, uint8_t * outBuffer) {
    outBuffer[0] = readingsIn->ws & 0x00FF;            // LSB Wind speed, Average over 1 minute
    outBuffer[1] = (readingsIn->ws & 0xFF00) >> 8;     // MSB
    outBuffer[2] = readingsIn->wsx & 0x00FF;           // Wind speed max measured over 1 second
    outBuffer[3] = (readingsIn->wsx & 0xFF00) >> 8;    // during the last averaging period
    outBuffer[4] = readingsIn->wsm & 0x00FF;           // Wind speed min measured over 1 second
    outBuffer[5] = (readingsIn->wsm & 0xFF00) >> 8;    // during the last averaging period
    outBuffer[6] = readingsIn->wd & 0x00FF;            // Wind Direction
    outBuffer[7] = (readingsIn->wd & 0xFF00) >> 8;     //
    outBuffer[8] = readingsIn->tmp & 0x00FF;           // Temperature
    outBuffer[9] = (readingsIn->tmp & 0xFF00) >> 8;    //
    outBuffer[10] = readingsIn->press & 0x00FF;        // Pressure
    outBuffer[11] = (readingsIn->press & 0xFF00) >> 8; //
    outBuffer[12] = readingsIn->hum & 0x00FF;          // Humidity
    outBuffer[13] = (readingsIn->hum & 0xFF00) >> 8;   //
    outBuffer[14] = readingsIn->bv & 0x00FF;           // Battery voltage
    outBuffer[15] = (readingsIn->bv & 0xFF00) >> 8;    //

    return 16;
}
uint16_t pack_WindOpDataReadings_t4(struct WindOpDataPacket_t3 * readingsIn, uint8_t * outBuffer) {
    outBuffer[0] = readingsIn->ws & 0x00FF;            // LSB Wind speed, Average over 1 minute
    outBuffer[1] = (readingsIn->ws & 0xFF00) >> 8;     // MSB
    outBuffer[2] = readingsIn->wsx & 0x00FF;           // Wind speed max measured over 1 second
    outBuffer[3] = (readingsIn->wsx & 0xFF00) >> 8;    // during the last averaging period
    outBuffer[4] = readingsIn->wsm & 0x00FF;           // Wind speed min measured over 1 second
    outBuffer[5] = (readingsIn->wsm & 0xFF00) >> 8;    // during the last averaging period
    outBuffer[6] = readingsIn->wd & 0x00FF;            // Wind Direction
    outBuffer[7] = (readingsIn->wd & 0xFF00) >> 8;     //

    return 8;
}

uint16_t pack_WindOpDataReadings_t5(struct WindOpDataPacket_t3 * readingsIn, uint8_t * outBuffer) {
    outBuffer[0] = readingsIn->tmp & 0x00FF;          // Temperature
    outBuffer[1] = (readingsIn->tmp & 0xFF00) >> 8;   //
    outBuffer[2] = readingsIn->press & 0x00FF;        // Pressure
    outBuffer[3] = (readingsIn->press & 0xFF00) >> 8; //
    outBuffer[4] = readingsIn->hum & 0x00FF;          // Humidity
    outBuffer[5] = (readingsIn->hum & 0xFF00) >> 8;   //
    outBuffer[6] = readingsIn->bv & 0x00FF;           // Battery voltage
    outBuffer[7] = (readingsIn->bv & 0xFF00) >> 8;    //

    return 8;
}

/* ****************************************************************************
 *
 * Reverse the PACK
 *
 * */
uint16_t unpack_WindOpDataReadings_t3(struct WindOpDataPacket_t3 * readingsIn, uint8_t * outBuffer) {
    readingsIn->ws = ((outBuffer[1] & 0xFF) << 8) + (outBuffer[0] & 0xFF);
    readingsIn->wsx = ((outBuffer[3] & 0xFF) << 8) + (outBuffer[2] & 0xFF);
    readingsIn->wsm = ((outBuffer[5] & 0xFF) << 8) + (outBuffer[4] & 0xFF);
    readingsIn->wd = ((outBuffer[7] & 0xFF) << 8) + (outBuffer[6] & 0xFF);
    readingsIn->tmp = ((outBuffer[9] & 0xFF) << 8) + (outBuffer[8] & 0xFF);
    readingsIn->press = ((outBuffer[11] & 0xFF) << 8) + (outBuffer[10] & 0xFF);
    readingsIn->hum = ((outBuffer[13] & 0xFF) << 8) + (outBuffer[12] & 0xFF);
    readingsIn->bv = ((outBuffer[15] & 0xFF) << 8) + (outBuffer[14] & 0xFF);
    return 16;
}

uint16_t unpack_WindOpDataReadings_t4(struct WindOpDataPacket_t3 * readingsIn, uint8_t * outBuffer) {
    readingsIn->ws = ((outBuffer[1] & 0xFF) << 8) + (outBuffer[0] & 0xFF);
    readingsIn->wsx = ((outBuffer[3] & 0xFF) << 8) + (outBuffer[2] & 0xFF);
    readingsIn->wsm = ((outBuffer[5] & 0xFF) << 8) + (outBuffer[4] & 0xFF);
    readingsIn->wd = ((outBuffer[7] & 0xFF) << 8) + (outBuffer[6] & 0xFF);
    return 8;
}

uint16_t unpack_WindOpDataReadings_t5(struct WindOpDataPacket_t3 * readingsIn, uint8_t * outBuffer) {
    readingsIn->tmp = ((outBuffer[1] & 0xFF) << 8) + (outBuffer[0] & 0xFF);
    readingsIn->press = ((outBuffer[3] & 0xFF) << 8) + (outBuffer[2] & 0xFF);
    readingsIn->hum = ((outBuffer[5] & 0xFF) << 8) + (outBuffer[4] & 0xFF);
    readingsIn->bv = ((outBuffer[7] & 0xFF) << 8) + (outBuffer[6] & 0xFF);
    return 8;
}

/* ****************************************************************************
 *
 * Full packet packing procedure.
 *
 * */
uint16_t pack_WindOpDataPacket(struct packCtrl * pack, uint8_t * outBuffer) {
    uint8_t i;
    uint8_t * bufferSize;

    // Write the packet type
    outBuffer[0] = pack->dataType;

    bufferSize = &outBuffer[1]; // Create a pointer to the BufferSize location
    *bufferSize = 2;            // Set the size as the packet so far

    // Pack the TIME
    *bufferSize += pack_WindOpMinuteTime(&pack->time, &outBuffer[*bufferSize], pack->incSeconds);

    // Iterate over the readings adding them to the byte buffer
    for (i = 0; i < pack->numOfReadings; i++) {
        printf("Buffer %3d start location is %4d\n", i, *bufferSize);
        switch (pack->dataType) {
        case WINDOPDATAPACKET_T3_TYPE:
            *bufferSize += pack_WindOpDataReadings_t3(&pack->readings[i], &outBuffer[*bufferSize]);
            break;
        case WINDOPDATAPACKET_T4_TYPE:
            *bufferSize += pack_WindOpDataReadings_t4(&pack->readings[i], &outBuffer[*bufferSize]);
            break;
        case WINDOPDATAPACKET_T5_TYPE:
            *bufferSize += pack_WindOpDataReadings_t5(&pack->readings[i], &outBuffer[*bufferSize]);
            break;
        case WINDOPDATAPACKET_T6_TYPE:
            *bufferSize += pack_WindOpDataReadings_t6(&pack->readings[i], &outBuffer[*bufferSize]);
            break;
        default:
            printf("ERROR data type %d is not supported\n", pack->dataType);
        }
    }

    return *bufferSize; // This contains the packet length
}

/* ****************************************************************************
 *
 * The unpack
 *
 * */
uint16_t unpack_WindOpDataPacket(struct packCtrl * pack, uint8_t * outBuffer) {
    uint8_t i;
    uint8_t bufferSize;
    uint8_t bufferAddress;

    pack->dataType = outBuffer[0];
    bufferSize = outBuffer[1];

    bufferAddress = 2;
    bufferAddress += unpack_WindOpMinuteTime(&pack->time, &outBuffer[bufferAddress]);

    i = 0;
    while (bufferAddress < bufferSize) {
        printf("Buffer %3d location is %4d Size: %4d\n", i, bufferAddress, bufferSize);
        switch (pack->dataType) {
        case WINDOPDATAPACKET_T3_TYPE:
            bufferAddress += unpack_WindOpDataReadings_t3(&pack->readings[i++], &outBuffer[bufferAddress]);
            break;
        case WINDOPDATAPACKET_T4_TYPE:
            bufferAddress += unpack_WindOpDataReadings_t4(&pack->readings[i++], &outBuffer[bufferAddress]);
            break;
        case WINDOPDATAPACKET_T5_TYPE:
            bufferAddress += unpack_WindOpDataReadings_t5(&pack->readings[i++], &outBuffer[bufferAddress]);
            break;
        default:
            printf("ERROR data type %d is not supported\n", pack->dataType);
        }
    }

    return i; // return the number of received packets
}

/* ****************************************************************************
 * ****************************************************************************
 * ***              PACKING FUNCTIONS OF INTEREST END                   *******
 * ****************************************************************************
 * ****************************************************************************
 * */

typedef struct testCtrl {

    packCtrl dataIn;
    packCtrl dataOut;

} testCtrl;

/* ****************************************************************************
 *
 * Pack and unpack the data checking the result
 *
 * */

uint16_t runTest(struct testCtrl * tstCtrl) {

    uint8_t bufferLength = 0;
    uint8_t i = 0;
    uint8_t unpackedBuffers = 0;
    uint8_t byteBuffer[BYTEBUFFERSIZE];

    dump_StrWithBreaker("Pack data");
    bufferLength = pack_WindOpDataPacket(&tstCtrl->dataIn, byteBuffer);

    dump_StrWithBreaker("Data buffer displayed as Byte HEX string");
    for (i = 0; i < bufferLength; i++) {
        printf("%02x ", byteBuffer[i]);
    }
    printf("\n");

    dump_StrWithBreaker("UN - pack data");
    unpackedBuffers = unpack_WindOpDataPacket(&tstCtrl->dataOut, byteBuffer);

    dump_StrWithBreaker("Test times and buffer data");
    uint16_t error = test_WindOpMinuteTime(&tstCtrl->dataIn.time, &tstCtrl->dataOut.time);
    for (i = 0; i < unpackedBuffers; i++) {
        printf("************************* Buffer %d\n", i);
        error += test_WindOpDataReadings(&tstCtrl->dataIn.readings[i], &tstCtrl->dataOut.readings[i], tstCtrl->dataIn.dataType);
    }

    return error;
}

/* ****************************************************************************
 *
 * This software is an example of how to encode and decode data packet
 * formats, with some basic test boilerplate.
 *
 * It should ..NOT.. be viewed as deployable code.
 *
 * */

int main(void) {

    uint16_t error = 0;
    testCtrl tstCtrl;

    dump_StrWithBreaker("Setup our test data");

    dump_StrWithBreaker("Minute time format");
    setExampleTime(&tstCtrl.dataIn.time, 2017, 12, 1, 12, 3, 00);
    setdataPoint(&tstCtrl.dataIn.readings[0], 5000, 5500, 4500);
    setdataPoint(&tstCtrl.dataIn.readings[1], 6000, 6500, 5500);
    tstCtrl.dataIn.incSeconds = 0;
    tstCtrl.dataIn.dataType = WINDOPDATAPACKET_T4_TYPE;
    tstCtrl.dataIn.numOfReadings = 3;

    error += runTest(&tstCtrl);

    dump_StrWithBreaker("Extended second time format");
    setExampleTime(&tstCtrl.dataIn.time, 2017, 12, 1, 12, 3, 44);
    setdataPoint(&tstCtrl.dataIn.readings[0], 5000, 5500, 4500);
    setdataPoint(&tstCtrl.dataIn.readings[1], 6000, 6500, 5500);
    setdataPoint(&tstCtrl.dataIn.readings[12], 1234, 1111, 2222);
    tstCtrl.dataIn.incSeconds = 1;
    tstCtrl.dataIn.dataType = WINDOPDATAPACKET_T3_TYPE;
    tstCtrl.dataIn.numOfReadings = 2;

    error += runTest(&tstCtrl);

    dump_StrWithBreaker("Extended second time format");
    setExampleTime(&tstCtrl.dataIn.time, 2017, 12, 1, 12, 30, 12);
    setdataPoint(&tstCtrl.dataIn.readings[0], 5000, 5500, 4500);
    setdataPoint(&tstCtrl.dataIn.readings[1], 6000, 6500, 5500);
    setdataPoint(&tstCtrl.dataIn.readings[12], 1234, 1111, 2222);
    tstCtrl.dataIn.incSeconds = 1;
    tstCtrl.dataIn.dataType = WINDOPDATAPACKET_T5_TYPE;
    tstCtrl.dataIn.numOfReadings = 1;

    error += runTest(&tstCtrl);

    if (error > 0) {
        dump_StrWithBreaker("TEST FAILED");
    } else {
        dump_StrWithBreaker("TEST PASSED");
    }

    return EXIT_SUCCESS;
}

