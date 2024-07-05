/**
 * \file IfxCcu6.c
 * \brief CCU6  basic functionality
 *
 * \version iLLD_1_0_1_16_1
 * \copyright Copyright (c) 2022 Infineon Technologies AG. All rights reserved.
 *
 *
 *
 *                                 IMPORTANT NOTICE
 *
 * Use of this file is subject to the terms of use agreed between (i) you or
 * the company in which ordinary course of business you are acting and (ii)
 * Infineon Technologies AG or its licensees. If and as long as no such terms
 * of use are agreed, use of this file is subject to following:
 *
 * Boost Software License - Version 1.0 - August 17th, 2003
 *
 * Permission is hereby granted, free of charge, to any person or organization
 * obtaining a copy of the software and accompanying documentation covered by
 * this license (the "Software") to use, reproduce, display, distribute,
 * execute, and transmit the Software, and to prepare derivative works of the
 * Software, and to permit third-parties to whom the Software is furnished to
 * do so, all subject to the following:
 *
 * The copyright notices in the Software and this entire statement, including
 * the above license grant, this restriction and the following disclaimer, must
 * be included in all copies of the Software, in whole or in part, and all
 * derivative works of the Software, unless such copies or derivative works are
 * solely in the form of machine-executable object code generated by a source
 * language processor.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
 * SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
 * FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *
 *
 *
 */

/******************************************************************************/
/*----------------------------------Includes----------------------------------*/
/******************************************************************************/

#include "IfxCcu6.h"

/******************************************************************************/
/*-------------------------Function Implementations---------------------------*/
/******************************************************************************/

void IfxCcu6_connectTrigger(Ifx_CCU6 *ccu6, IfxCcu6_TrigOut outputLine, IfxCcu6_TrigSel selectedTrigger)
{
    unsigned mosel = ccu6->MOSEL.U;
    uint16   shift = (uint16)outputLine;
    uint16   data  = 2 * selectedTrigger;

    if (ccu6 == &MODULE_CCU61)
    {
        data = data + 1;
    }

    mosel         = ccu6->MOSEL.U;
    __ldmst_c(&mosel, (0x7U << shift), (data << shift));
    ccu6->MOSEL.U = mosel;
}


void IfxCcu6_disableModulationOutput(Ifx_CCU6 *ccu6, IfxCcu6_TimerId timer, IfxCcu6_ChannelOut channelOut)
{
    uint32 shift, mask;

    if (timer != IfxCcu6_TimerId_t13)
    {
        if (channelOut != IfxCcu6_ChannelOut_cout3)
        {
            shift          = channelOut;
            mask           = (1 << shift);
            ccu6->MODCTR.U = ccu6->MODCTR.U & ~(mask);
        }
        else
        {}
    }
    else
    {
        if (channelOut != IfxCcu6_ChannelOut_cout3)
        {
            shift          = channelOut + 8;
            mask           = (1 << shift);
            ccu6->MODCTR.U = ccu6->MODCTR.U & ~(mask);
        }
        else
        {
            ccu6->MODCTR.B.ECT13O = FALSE;
        }
    }
}


void IfxCcu6_disableModule(Ifx_CCU6 *ccu6)
{
    uint16 passwd = IfxScuWdt_getCpuWatchdogPassword();
    IfxScuWdt_clearCpuEndinit(passwd);
    ccu6->CLC.U = 0x00000001;
    IfxScuWdt_setCpuEndinit(passwd);

    /* Wait until module is disabled */
    while (IfxCcu6_isModuleEnabled(ccu6) == TRUE)
    {}
}


void IfxCcu6_enableModulationOutput(Ifx_CCU6 *ccu6, IfxCcu6_TimerId timer, IfxCcu6_ChannelOut channelOut)
{
    uint32 shift, mask;

    if (timer != IfxCcu6_TimerId_t13)
    {
        if (channelOut != IfxCcu6_ChannelOut_cout3)
        {
            shift          = channelOut;
            mask           = (1 << shift);
            ccu6->MODCTR.U = ccu6->MODCTR.U | (mask);
        }
        else
        {}
    }
    else
    {
        if (channelOut != IfxCcu6_ChannelOut_cout3)
        {
            shift          = channelOut + 8;
            mask           = (1 << shift);
            ccu6->MODCTR.U = ccu6->MODCTR.U | (mask);
        }
        else
        {
            ccu6->MODCTR.B.ECT13O = TRUE;
        }
    }
}


void IfxCcu6_enableModule(Ifx_CCU6 *ccu6)
{
    uint16 passwd = IfxScuWdt_getCpuWatchdogPassword();
    IfxScuWdt_clearCpuEndinit(passwd);
    ccu6->CLC.B.DISR = 0U; /* Enable module */
    IfxScuWdt_setCpuEndinit(passwd);

    /* Wait until module is enabled */
    while (IfxCcu6_isModuleEnabled(ccu6) == FALSE)
    {}
}


Ifx_CCU6 *IfxCcu6_getAddress(IfxCcu6_Index ccu6)
{
    Ifx_CCU6 *module;

    if (ccu6 < IFXCCU6_NUM_MODULES)
    {
        module = (Ifx_CCU6 *)IfxCcu6_cfg_indexMap[ccu6].module;
    }
    else
    {
        module = NULL_PTR;
    }

    return module;
}


uint32 IfxCcu6_getCaptureRegisterValue(Ifx_CCU6 *ccu6, IfxCcu6_T12Channel channel)
{
    return ccu6->CC6R[channel].U;
}


uint32 IfxCcu6_getCaptureShadowRegisterValue(Ifx_CCU6 *ccu6, IfxCcu6_T12Channel channel)
{
    return ccu6->CC6SR[channel].U;
}


IfxCcu6_Index IfxCcu6_getIndex(Ifx_CCU6 *ccu6)
{
    uint32        index;
    IfxCcu6_Index result;

    result = IfxCcu6_Index_none;

    for (index = 0; index < IFXCCU6_NUM_MODULES; index++)
    {
        if (IfxCcu6_cfg_indexMap[index].module == ccu6)
        {
            result = (IfxCcu6_Index)IfxCcu6_cfg_indexMap[index].index;
            break;
        }
    }

    return result;
}


volatile Ifx_SRC_SRCR *IfxCcu6_getSrcAddress(Ifx_CCU6 *ccu6, IfxCcu6_ServiceRequest serviceRequest)
{
    sint32                 moduleIdx = IfxCcu6_getIndex(ccu6);
    volatile Ifx_SRC_SRCR *srcr;

    srcr = &(MODULE_SRC.CCU6.CCU[moduleIdx].SR[0]);

    return &(srcr[serviceRequest]);
}


uint32 IfxCcu6_readTimer(Ifx_CCU6 *ccu6, IfxCcu6_TimerId timer)
{
    uint32 result = 0;

    if (timer != IfxCcu6_TimerId_t13)
    {
        result = ccu6->T12.U;
    }
    else
    {
        result = ccu6->T13.U;
    }

    return result;
}


void IfxCcu6_resetModule(Ifx_CCU6 *ccu6)
{
    uint16 passwd = IfxScuWdt_getCpuWatchdogPassword();

    IfxScuWdt_clearCpuEndinit(passwd);
    ccu6->KRST0.B.RST = 1;          /* Only if both Kernel reset bits are set a reset is executed */
    ccu6->KRST1.B.RST = 1;
    IfxScuWdt_setCpuEndinit(passwd);

    while (0 == ccu6->KRST0.B.RSTSTAT)  /* Wait until reset is executed */

    {}

    IfxScuWdt_clearCpuEndinit(passwd);
    ccu6->KRSTCLR.B.CLR = 1;            /* Clear Kernel reset status bit */
    IfxScuWdt_setCpuEndinit(passwd);
}


void IfxCcu6_routeInterruptNode(Ifx_CCU6 *ccu6, IfxCcu6_InterruptSource source, IfxCcu6_ServiceRequest serviceRequest)
{
    if ((source == IfxCcu6_InterruptSource_cc60RisingEdge) || (source == IfxCcu6_InterruptSource_cc60FallingEdge))
    {
        ccu6->INP.B.INPCC60 = serviceRequest;
    }
    else if ((source == IfxCcu6_InterruptSource_cc61RisingEdge) || (source == IfxCcu6_InterruptSource_cc61FallingEdge))
    {
        ccu6->INP.B.INPCC61 = serviceRequest;
    }
    else if ((source == IfxCcu6_InterruptSource_cc62RisingEdge) || (source == IfxCcu6_InterruptSource_cc62FallingEdge))
    {
        ccu6->INP.B.INPCC62 = serviceRequest;
    }
    else if ((source == IfxCcu6_InterruptSource_correctHallEvent))
    {
        ccu6->INP.B.INPCHE = serviceRequest;
    }
    else if ((source == IfxCcu6_InterruptSource_trap) || (source == IfxCcu6_InterruptSource_wrongHallEvent))
    {
        ccu6->INP.B.INPERR = serviceRequest;
    }
    else if ((source == IfxCcu6_InterruptSource_t12OneMatch) || (source == IfxCcu6_InterruptSource_t12PeriodMatch))
    {
        ccu6->INP.B.INPT12 = serviceRequest;
    }
    else if ((source == IfxCcu6_InterruptSource_t13CompareMatch) || (source == IfxCcu6_InterruptSource_t13PeriodMatch))
    {
        ccu6->INP.B.INPT13 = serviceRequest;
    }
    else
    {
        __debug();
    }
}


void IfxCcu6_setOutputPassiveLevel(Ifx_CCU6 *ccu6, IfxCcu6_ChannelOut channelOut, boolean state)
{
    if (channelOut != IfxCcu6_ChannelOut_cout3)
    {
        uint32 shift = channelOut;
        uint32 mask  = (1 << shift);
        ccu6->PSLR.U = (ccu6->PSLR.U & ~mask) | ((uint32)state << shift);
    }
    else
    {
        ccu6->PSLR.B.PSL63 = state;
    }
}


void IfxCcu6_setT12CaptureCompareState(Ifx_CCU6 *ccu6, IfxCcu6_T12Channel channel, IfxCcu6_CaptureCompareState state)
{
    uint32 mask = (0x0101U << channel);
    uint32 mode;

    if (state == IfxCcu6_CaptureCompareState_set)
    {
        mode             = 0x0001U;
        ccu6->CMPMODIF.U = (ccu6->CMPMODIF.U & ~mask) | (mode << channel);
    }

    if (state == IfxCcu6_CaptureCompareState_clear)
    {
        mode             = 0x0100U;
        ccu6->CMPMODIF.U = (ccu6->CMPMODIF.U & ~mask) | (mode << channel);
    }

    if (state == IfxCcu6_CaptureCompareState_toggle)
    {
        mode             = 0x0101U;
        ccu6->CMPMODIF.U = (ccu6->CMPMODIF.U & ~mask) | (mode << channel);
    }
}


void IfxCcu6_setT12CompareValue(Ifx_CCU6 *ccu6, IfxCcu6_T12Channel channel, uint16 value)
{
    ccu6->CC6SR[channel].B.CCS = value;
}


float32 IfxCcu6_setT12Frequency(Ifx_CCU6 *ccu6, float32 frequency, Ifx_TimerValue period, IfxCcu6_T12CountMode countMode)
{
    uint16  prescaler;
    float32 freqCC6   = IfxScuCcu_getSpbFrequency();
    uint16  divFactor = freqCC6 / frequency;

    for (prescaler = 0; prescaler < 16; prescaler++)
    {
        divFactor = divFactor / 2;

        if (divFactor == (uint8)0)
        {
            break;
        }
    }

    if (prescaler < 16)
    {
        uint16                  periodVal;
        boolean                 additionalPrescaler;
        IfxCcu6_TimerInputClock clockInput;

        periodVal = (uint16)((countMode != IfxCcu6_T12CountMode_edgeAligned) ? ((period / 2) - 1) : (period - 1));
        IfxCcu6_setT12PeriodValue(ccu6, periodVal);
        IfxCcu6_enableShadowTransfer(ccu6, TRUE, FALSE);

        clockInput = (IfxCcu6_TimerInputClock)(prescaler & 0x7U);
        IfxCcu6_setInputClockFrequency(ccu6, IfxCcu6_TimerId_t12, clockInput);

        additionalPrescaler = ((prescaler & 0x8U) != 0);

        if (additionalPrescaler)
        {
            IfxCcu6_enableAdditionalPrescaler(ccu6, IfxCcu6_TimerId_t12);
        }

        IfxCcu6_setT12CountMode(ccu6, countMode);

        frequency = freqCC6 / (0x1u << prescaler); // Frequency = FREQ_CCU6 / (2 ^ prescaler)
    }
    else
    {
        frequency = 0;
    }

    return frequency;
}


void IfxCcu6_setT12InputSignal(Ifx_CCU6 *ccu6, IfxCcu6_T12hr_In *extInput)
{
    ccu6->PISEL2.B.T12EXT  = extInput->select >= Ifx_RxSel_e;
    ccu6->PISEL0.B.IST12HR = extInput->select;

    IFX_ASSERT(IFX_VERBOSE_LEVEL_ERROR, extInput->module == ccu6);
}


void IfxCcu6_setT13CaptureCompareState(Ifx_CCU6 *ccu6, IfxCcu6_CaptureCompareState state)
{
    uint32 shift = 6;
    uint32 mask  = (0x0101U << shift);
    uint32 mode;

    if (state == IfxCcu6_CaptureCompareState_set)
    {
        mode             = 0x0001U;
        ccu6->CMPMODIF.U = (ccu6->CMPMODIF.U & ~mask) | (mode << shift);
    }

    if (state == IfxCcu6_CaptureCompareState_clear)
    {
        mode             = 0x0100U;
        ccu6->CMPMODIF.U = (ccu6->CMPMODIF.U & ~mask) | (mode << shift);
    }

    if (state == IfxCcu6_CaptureCompareState_toggle)
    {
        mode             = 0x0101U;
        ccu6->CMPMODIF.U = (ccu6->CMPMODIF.U & ~mask) | (mode << shift);
    }
}


float32 IfxCcu6_setT13Frequency(Ifx_CCU6 *ccu6, float32 frequency, Ifx_TimerValue period)
{
    uint16  prescaler;
    float32 freqCC6   = IfxScuCcu_getSpbFrequency();
    uint16  divFactor = freqCC6 / frequency;

    for (prescaler = 0; prescaler < 16; prescaler++)
    {
        divFactor = divFactor / 2;

        if (divFactor == (uint8)0)
        {
            break;
        }
    }

    if (prescaler < 16)
    {
        uint16                  periodVal;
        boolean                 additionalPrescaler;
        IfxCcu6_TimerInputClock clockInput;

        periodVal = (uint16)(period - 1);
        IfxCcu6_setT13PeriodValue(ccu6, periodVal);
        IfxCcu6_enableShadowTransfer(ccu6, FALSE, TRUE);

        clockInput = (IfxCcu6_TimerInputClock)(prescaler & 0x7U);
        IfxCcu6_setInputClockFrequency(ccu6, IfxCcu6_TimerId_t13, clockInput);

        additionalPrescaler = ((prescaler & 0x8U) != 0);

        if (additionalPrescaler)
        {
            IfxCcu6_enableAdditionalPrescaler(ccu6, IfxCcu6_TimerId_t13);
        }

        frequency = freqCC6 / (0x1u << prescaler); // Frequency = FREQ_CCU6 / (2 ^ prescaler)
    }
    else
    {
        /** \retval IfxCcu6_Stat_wrongPwmFreq if the T12 prescaler can't fulfill the
         * required frequency */
        frequency = 0;
    }

    return frequency;
}


void IfxCcu6_setT13InputSignal(Ifx_CCU6 *ccu6, IfxCcu6_T13hr_In *extInput)
{
    ccu6->PISEL2.B.T13EXT  = extInput->select >= Ifx_RxSel_e;
    ccu6->PISEL2.B.IST13HR = extInput->select;

    IFX_ASSERT(IFX_VERBOSE_LEVEL_ERROR, extInput->module == ccu6);
}
