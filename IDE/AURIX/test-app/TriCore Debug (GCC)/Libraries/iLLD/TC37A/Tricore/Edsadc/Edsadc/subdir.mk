################################################################################
# Automatically-generated file. Do not edit!
################################################################################

# Add inputs and outputs from these tool invocations to the build variables 
C_SRCS += \
../Libraries/iLLD/TC37A/Tricore/Edsadc/Edsadc/IfxEdsadc_Edsadc.c 

C_DEPS += \
./Libraries/iLLD/TC37A/Tricore/Edsadc/Edsadc/IfxEdsadc_Edsadc.d 

OBJS += \
./Libraries/iLLD/TC37A/Tricore/Edsadc/Edsadc/IfxEdsadc_Edsadc.o 


# Each subdirectory must supply rules for building sources it contributes
Libraries/iLLD/TC37A/Tricore/Edsadc/Edsadc/%.o: ../Libraries/iLLD/TC37A/Tricore/Edsadc/Edsadc/%.c Libraries/iLLD/TC37A/Tricore/Edsadc/Edsadc/subdir.mk
	@echo 'Building file: $<'
	@echo 'Invoking: AURIX GCC Compiler'
	tricore-elf-gcc -std=c99 "@C:/Users/spewl/workspace/repos/wolfBoot/IDE/AURIX/test-app/TriCore Debug (GCC)/AURIX_GCC_Compiler-Include_paths__-I_.opt" -O0 -g3 -Wall -c -fmessage-length=0 -fno-common -fstrict-volatile-bitfields -fdata-sections -ffunction-sections -mtc162 -MMD -MP -MF"$(@:%.o=%.d)" -MT"$@" -o "$@" "$<"
	@echo 'Finished building: $<'
	@echo ' '


clean: clean-Libraries-2f-iLLD-2f-TC37A-2f-Tricore-2f-Edsadc-2f-Edsadc

clean-Libraries-2f-iLLD-2f-TC37A-2f-Tricore-2f-Edsadc-2f-Edsadc:
	-$(RM) ./Libraries/iLLD/TC37A/Tricore/Edsadc/Edsadc/IfxEdsadc_Edsadc.d ./Libraries/iLLD/TC37A/Tricore/Edsadc/Edsadc/IfxEdsadc_Edsadc.o

.PHONY: clean-Libraries-2f-iLLD-2f-TC37A-2f-Tricore-2f-Edsadc-2f-Edsadc

