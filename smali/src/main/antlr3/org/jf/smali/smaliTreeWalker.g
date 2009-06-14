/*
 * [The "BSD licence"]
 * Copyright (c) 2009 Ben Gruver
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
 
tree grammar smaliTreeWalker;

options {
	tokenVocab=smaliParser;
	ASTLabelType=CommonTree;
}

@header {
package org.jf.smali;

import java.util.HashMap;

import org.jf.dexlib.*;
import org.jf.dexlib.EncodedValue.*;
import org.jf.dexlib.util.*;
import org.jf.dexlib.code.*;
import org.jf.dexlib.code.Format.*;
}

@members {
	public DexFile dexFile;
	public ClassDefItem classDefItem;
	public ClassDataItem classDataItem;

	private byte parseRegister_nibble(String register, int totalMethodRegisters, int methodParameterRegisters)
		throws SemanticException {
		//register should be in the format "v12"		
		int val = Byte.parseByte(register.substring(1));
		if (register.charAt(0) == 'p') {
			val = totalMethodRegisters - methodParameterRegisters + val;
		}		
		if (val >= 2<<4) {
			throw new SemanticException(input, "The maximum allowed register in this context is list of registers is v15");
		}
		//the parser wouldn't have accepted a negative register, i.e. v-1, so we don't have to check for val<0;
		return (byte)val;
	}
	
	//return a short, because java's byte is signed
	private short parseRegister_byte(String register, int totalMethodRegisters, int methodParameterRegisters)
		throws SemanticException {
		//register should be in the format "v123"
		int val = Short.parseShort(register.substring(1));
		if (register.charAt(0) == 'p') {
			val = totalMethodRegisters - methodParameterRegisters + val;
		}
		if (val >= 2<<8) {
			throw new SemanticException(input, "The maximum allowed register in this context is v255");
		}
		return (short)val;
	}
	
	//return an int because java's short is signed
	private int parseRegister_short(String register, int totalMethodRegisters, int methodParameterRegisters)
		throws SemanticException {
		//register should be in the format "v12345"		
		int val = Integer.parseInt(register.substring(1));
		if (register.charAt(0) == 'p') {
			val = totalMethodRegisters - methodParameterRegisters + val;
		}
		if (val >= 2<<16) {
			throw new SemanticException(input, "The maximum allowed register in this context is v65535");
		}
		//the parser wouldn't accept a negative register, i.e. v-1, so we don't have to check for val<0;
		return val;
	}
	
	public String getErrorMessage(RecognitionException e, String[] tokenNames) {
		if ( e instanceof SemanticException ) {
			return e.getMessage();
		} else {
			return super.getErrorMessage(e, tokenNames);
		}
	}
	
	public String getErrorHeader(RecognitionException e) {
		return getSourceName()+"["+ e.line+","+e.charPositionInLine+"]";
	}
}



smali_file
	:	^(I_CLASS_DEF header methods fields annotations)
	{
		AnnotationDirectoryItem annotationDirectoryItem = null;
		
		if (	$methods.methodAnnotationSets != null ||
			$methods.parameterAnnotationSets != null ||
			$fields.fieldAnnotationSets != null ||
			$annotations.annotationSetItem != null) {
			annotationDirectoryItem = new AnnotationDirectoryItem(
				dexFile,
				$annotations.annotationSetItem,
				$fields.fieldAnnotationSets,
				$methods.methodAnnotationSets,
				$methods.parameterAnnotationSets);
		}
		
		classDefItem.setAnnotations(annotationDirectoryItem);
	};
	catch [Exception ex] {
		reportError(new SemanticException(input, ex));
	}


header	returns[TypeIdItem classType, int accessFlags, TypeIdItem superType, TypeListItem implementsList, StringIdItem sourceSpec]
:	class_spec super_spec implements_list source_spec
	{
		//TODO: if a class has no fields or methods, it shouldn't have a ClassDataItem
		classDataItem = new ClassDataItem(dexFile, 0);
		classDefItem = new ClassDefItem(dexFile, $class_spec.type, $class_spec.accessFlags, 
			$super_spec.type, $implements_list.implementsList, $source_spec.source, classDataItem);
	};

class_spec returns[TypeIdItem type, int accessFlags]
	:	class_type_descriptor access_list
	{
		$type = $class_type_descriptor.type;
		$accessFlags = $access_list.value;
	};

super_spec returns[TypeIdItem type]
	:	^(I_SUPER class_type_descriptor)
	{
		$type = $class_type_descriptor.type;
	};
	

implements_spec returns[TypeIdItem type]
	:	^(I_IMPLEMENTS class_type_descriptor)
	{
		$type = $class_type_descriptor.type;
	};
	
implements_list returns[TypeListItem implementsList]
@init	{ ArrayList<TypeIdItem> typeList; }
	:	{typeList = new ArrayList<TypeIdItem>();}
		(implements_spec {typeList.add($implements_spec.type);} )*
		{if (typeList.size() > 0) $implementsList = new TypeListItem(dexFile, typeList);
		else $implementsList = null;};
		
source_spec returns[StringIdItem source]
	:	{$source = null;}
		^(I_SOURCE string_literal {$source = new StringIdItem(dexFile, $string_literal.value);})
	|	;
		
	

access_list returns [int value]
	@init
	{
		$value = 0;
	}
	:	^(I_ACCESS_LIST
			(
				ACCESS_SPEC
				{
					$value |= AccessFlags.getAccessFlag($ACCESS_SPEC.getText()).getValue();
				}
			)+);

fields returns[List<AnnotationDirectoryItem.FieldAnnotation> fieldAnnotationSets]
	:	^(I_FIELDS
			(field
			{
				classDefItem.addField($field.encodedField, $field.encodedValue);
				if ($field.fieldAnnotationSet != null) {
					if ($fieldAnnotationSets == null) {
						$fieldAnnotationSets = new ArrayList<AnnotationDirectoryItem.FieldAnnotation>();
					}
					fieldAnnotationSets.add($field.fieldAnnotationSet);
				}
			})*);

methods returns[List<AnnotationDirectoryItem.MethodAnnotation> methodAnnotationSets,
		List<AnnotationDirectoryItem.ParameterAnnotation> parameterAnnotationSets]
	:	^(I_METHODS
			(method
			{
				classDataItem.addMethod($method.encodedMethod);
				if ($method.methodAnnotationSet != null) {
					if ($methodAnnotationSets == null) {
						$methodAnnotationSets = new ArrayList<AnnotationDirectoryItem.MethodAnnotation>();
					}
					$methodAnnotationSets.add($method.methodAnnotationSet);
				}
				if ($method.parameterAnnotationSets != null) {
					if ($parameterAnnotationSets == null) {
						$parameterAnnotationSets = new ArrayList<AnnotationDirectoryItem.ParameterAnnotation>();
					}
					$parameterAnnotationSets.add($method.parameterAnnotationSets);
				}
			})*);

field returns[ClassDataItem.EncodedField encodedField, EncodedValue encodedValue, AnnotationDirectoryItem.FieldAnnotation fieldAnnotationSet]
	:^(I_FIELD MEMBER_NAME access_list ^(I_FIELD_TYPE nonvoid_type_descriptor) field_initial_value annotations?)
	{
		TypeIdItem classType = classDefItem.getClassType();
		StringIdItem memberName = new StringIdItem(dexFile, $MEMBER_NAME.text);
		TypeIdItem fieldType = $nonvoid_type_descriptor.type;

		FieldIdItem fieldIdItem = new FieldIdItem(dexFile, classType, memberName, fieldType);
		$encodedField = new ClassDataItem.EncodedField(dexFile, fieldIdItem, $access_list.value);
		
		if ($field_initial_value.encodedValue != null) {
			if (($access_list.value & AccessFlags.STATIC.getValue()) == 0) {
				throw new SemanticException(input, "Initial field values can only be specified for static fields.");
			}
			
			$encodedValue = $field_initial_value.encodedValue;
		} else {
			$encodedValue = null;			
		}
		
		if ($annotations.annotationSetItem != null) {
			$fieldAnnotationSet = new AnnotationDirectoryItem.FieldAnnotation(dexFile, fieldIdItem, $annotations.annotationSetItem);
		}
	};


field_initial_value returns[EncodedValue encodedValue]
	:	^(I_FIELD_INITIAL_VALUE literal) {$encodedValue = $literal.encodedValue;}
	|	;

literal returns[EncodedValue encodedValue]
	:	integer_literal { $encodedValue = new EncodedValue(dexFile, new IntEncodedValueSubField($integer_literal.value)); }
	|	long_literal { $encodedValue = new EncodedValue(dexFile, new LongEncodedValueSubField($long_literal.value)); }
	|	short_literal { $encodedValue = new EncodedValue(dexFile, new ShortEncodedValueSubField($short_literal.value)); }
	|	byte_literal { $encodedValue = new EncodedValue(dexFile, new ByteEncodedValueSubField($byte_literal.value)); }
	|	float_literal { $encodedValue = new EncodedValue(dexFile, new FloatEncodedValueSubField($float_literal.value)); }
	|	double_literal { $encodedValue = new EncodedValue(dexFile, new DoubleEncodedValueSubField($double_literal.value)); }
	|	char_literal { $encodedValue = new EncodedValue(dexFile, new CharEncodedValueSubField($char_literal.value)); }
	|	string_literal { $encodedValue = new EncodedValue(dexFile, new EncodedIndexedItemReference(dexFile, new StringIdItem(dexFile, $string_literal.value))); }
	|	bool_literal { $encodedValue = new EncodedValue(dexFile, new BoolEncodedValueSubField($bool_literal.value)); }
	|	type_descriptor { $encodedValue = new EncodedValue(dexFile, new EncodedIndexedItemReference(dexFile, $type_descriptor.type)); }
	|	array_literal { $encodedValue = new EncodedValue(dexFile, new ArrayEncodedValueSubField(dexFile, $array_literal.values)); }
	|	subannotation { $encodedValue = new EncodedValue(dexFile, $subannotation.value); }
	|	field_literal { $encodedValue = new EncodedValue(dexFile, $field_literal.value); }
	|	method_literal { $encodedValue = new EncodedValue(dexFile, $method_literal.value); }
	|	enum_literal { $encodedValue = new EncodedValue(dexFile, $enum_literal.value); };
	
	
//everything but string
fixed_size_literal returns[byte[\] value]
	:	integer_literal { $value = literalTools.intToBytes($integer_literal.value); }
	|	long_literal { $value = literalTools.longToBytes($long_literal.value); }
	|	short_literal { $value = literalTools.shortToBytes($short_literal.value); }
	|	byte_literal { $value = new byte[] { $byte_literal.value }; }
	|	float_literal { $value = literalTools.floatToBytes($float_literal.value); }
	|	double_literal { $value = literalTools.doubleToBytes($double_literal.value); }
	|	char_literal { $value = literalTools.charToBytes($char_literal.value); }
	|	bool_literal { $value = literalTools.boolToBytes($bool_literal.value); };
	
//everything but string
fixed_64bit_literal returns[long value]
	:	integer_literal { $value = $integer_literal.value; }
	|	long_literal { $value = $long_literal.value; }
	|	short_literal { $value = $short_literal.value; }
	|	byte_literal { $value = $byte_literal.value; }
	|	float_literal { $value = Float.floatToRawIntBits($float_literal.value); }
	|	double_literal { $value = Double.doubleToRawLongBits($double_literal.value); }
	|	char_literal { $value = $char_literal.value; }
	|	bool_literal { $value = $bool_literal.value?1:0; };
	
//everything but string and double
//long is allowed, but it must fit into an int
fixed_32bit_literal returns[int value]
	:	integer_literal { $value = $integer_literal.value; }
	|	long_literal { literalTools.checkInt($long_literal.value); $value = (int)$long_literal.value; }
	|	short_literal { $value = $short_literal.value; }
	|	byte_literal { $value = $byte_literal.value; }
	|	float_literal { $value = Float.floatToRawIntBits($float_literal.value); }
	|	char_literal { $value = $char_literal.value; }
	|	bool_literal { $value = $bool_literal.value?1:0; };

array_elements returns[List<byte[\]> values]
	:	{$values = new ArrayList<byte[]>();}
		^(I_ARRAY_ELEMENTS
			(fixed_size_literal
			{
				$values.add($fixed_size_literal.value);				
			})*);	
			
packed_switch_target_count returns[int targetCount]
	:	I_PACKED_SWITCH_TARGET_COUNT {$targetCount = Integer.parseInt($I_PACKED_SWITCH_TARGET_COUNT.text);};

packed_switch_targets[int baseOffset] returns[int[\] targets]
	:
		^(I_PACKED_SWITCH_TARGETS
			packed_switch_target_count
			{
				int targetCount = $packed_switch_target_count.targetCount;
				$targets = new int[targetCount];
				int targetsPosition = 0;
			}
			
			(offset_or_label
			{
				targets[targetsPosition++] = $offset_or_label.offsetValue - $baseOffset;
			})*
		);

sparse_switch_target_count returns[int targetCount]
	:	I_SPARSE_SWITCH_TARGET_COUNT {$targetCount = Integer.parseInt($I_SPARSE_SWITCH_TARGET_COUNT.text);};
		
sparse_switch_keys[int targetCount] returns[int[\] keys]
	:	{
			$keys = new int[$targetCount];
			int keysPosition = 0;
		}
		^(I_SPARSE_SWITCH_KEYS
			(fixed_32bit_literal
			{
				$keys[keysPosition++] = $fixed_32bit_literal.value;		
			})*
		);
		
sparse_switch_targets[int baseOffset, int targetCount] returns[int[\] targets]
	:	{
			$targets = new int[$targetCount];
			int targetsPosition = 0;
		}
		^(I_SPARSE_SWITCH_TARGETS
			(offset_or_label
			{
				$targets[targetsPosition++] = $offset_or_label.offsetValue - $baseOffset;
			})*
		);
	
method returns[	ClassDataItem.EncodedMethod encodedMethod,
		AnnotationDirectoryItem.MethodAnnotation methodAnnotationSet,
		AnnotationDirectoryItem.ParameterAnnotation parameterAnnotationSets]
	scope
	{
		HashMap<String, Integer> labels;
		TryListBuilder tryList;
		int currentAddress;
		DebugInfoBuilder debugInfo;
	}
	@init
	{
		MethodIdItem methodIdItem = null;
		int totalMethodRegisters = 0;
		int methodParameterRegisters = 0;
		int accessFlags = 0;
		boolean isStatic = false;
	}
	:	{
			$method::labels = new HashMap<String, Integer>();
			$method::tryList = new TryListBuilder();
			$method::currentAddress = 0;
			$method::debugInfo = new DebugInfoBuilder();
		}
		^(	I_METHOD
			method_name_and_prototype
			access_list
			{
				methodIdItem = $method_name_and_prototype.methodIdItem;
				accessFlags = $access_list.value;
				isStatic = (accessFlags & AccessFlags.STATIC.getValue()) != 0; 
				methodParameterRegisters = methodIdItem.getParameterRegisterCount(isStatic);
			}
			registers_directive
			{
				totalMethodRegisters = $registers_directive.registers;
			}
			labels
			statements[totalMethodRegisters, methodParameterRegisters]
			catches
			parameters
			ordered_debug_directives[totalMethodRegisters, methodParameterRegisters]
			annotations
		)
	{	
		ArrayList<InstructionField> instructions = $statements.instructions;
		
		Pair<List<CodeItem.TryItem>, List<CodeItem.EncodedCatchHandler>> temp = $method::tryList.encodeTries(dexFile);
		List<CodeItem.TryItem> tries = temp.first;
		List<CodeItem.EncodedCatchHandler> handlers = temp.second;
	

		DebugInfoItem debugInfoItem = $method::debugInfo.encodeDebugInfo(dexFile);		
		
		CodeItem codeItem;
		
		if (totalMethodRegisters == 0 &&
		    instructions.size() == 0 &&
		    $method::labels.size()== 0 &&
		    (tries == null || tries.size() == 0) &&
		    (handlers == null || handlers.size() == 0) &&
		    debugInfoItem == null) {	
		    		    
			codeItem = null;
			
		} else {
			if (totalMethodRegisters < methodParameterRegisters) {
				throw new SemanticException(input, "This method requires at least " +
								Integer.toString(methodParameterRegisters) +
								" registers, for the method parameters");
			}
			
			int methodParameterCount = methodIdItem.getParameterCount();
			if ($method::debugInfo.getParameterNameCount() > methodParameterCount) {
				throw new SemanticException(input, "Too many parameter names specified. This method only has " +
								Integer.toString(methodParameterCount) +
								" parameters.");
			}
				
			codeItem = new CodeItem(dexFile,
						totalMethodRegisters,
						methodIdItem.getParameterRegisterCount(isStatic),
						instructions,
						debugInfoItem,
						tries,
						handlers);
		}
		
		$encodedMethod = new ClassDataItem.EncodedMethod(dexFile, methodIdItem, accessFlags, codeItem);
		
		if ($annotations.annotationSetItem != null) {
			$methodAnnotationSet = new AnnotationDirectoryItem.MethodAnnotation(dexFile, methodIdItem, $annotations.annotationSetItem);
		}
		
		if ($parameters.parameterAnnotations != null) {
			$parameterAnnotationSets = new AnnotationDirectoryItem.ParameterAnnotation(dexFile, methodIdItem, $parameters.parameterAnnotations);
		}
	};
	
method_prototype returns[ProtoIdItem protoIdItem]
	:	^(I_METHOD_PROTOTYPE ^(I_METHOD_RETURN_TYPE type_descriptor) field_type_list)
	{
		TypeIdItem returnType = $type_descriptor.type;
		ArrayList<TypeIdItem> parameterTypes = $field_type_list.types;
		
		$protoIdItem = new ProtoIdItem(dexFile, returnType, parameterTypes);
	};

method_name_and_prototype returns[MethodIdItem methodIdItem]
	:	MEMBER_NAME method_prototype
	{
		TypeIdItem classType = classDefItem.getClassType();
		String methodNameString = $MEMBER_NAME.text;
		StringIdItem methodName = new StringIdItem(dexFile, methodNameString);
		ProtoIdItem protoIdItem = $method_prototype.protoIdItem;

		$methodIdItem = new MethodIdItem(dexFile, classType, methodName, protoIdItem);
	};

field_type_list returns[ArrayList<TypeIdItem> types]
	@init
	{
		$types = new ArrayList<TypeIdItem>();
	}
	:	(
			nonvoid_type_descriptor
			{
				$types.add($nonvoid_type_descriptor.type);
			}
		)*;
	

fully_qualified_method returns[MethodIdItem methodIdItem]
	:	reference_type_descriptor MEMBER_NAME method_prototype
	{
		TypeIdItem classType = $reference_type_descriptor.type;
		StringIdItem methodName = new StringIdItem(dexFile, $MEMBER_NAME.text);
		ProtoIdItem prototype = $method_prototype.protoIdItem;
		$methodIdItem = new MethodIdItem(dexFile, classType, methodName, prototype);		
	};

fully_qualified_field returns[FieldIdItem fieldIdItem]
	:	reference_type_descriptor MEMBER_NAME nonvoid_type_descriptor
	{
		TypeIdItem classType = $reference_type_descriptor.type;
		StringIdItem fieldName = new StringIdItem(dexFile, $MEMBER_NAME.text);
		TypeIdItem fieldType = $nonvoid_type_descriptor.type;
		$fieldIdItem = new FieldIdItem(dexFile, classType, fieldName, fieldType);
	};

registers_directive returns[int registers]
	:	{$registers = 0;}
		^(I_REGISTERS (short_integral_literal {$registers = $short_integral_literal.value;} )? );
	
labels
	:	^(I_LABELS label_def*);
	
label_def
	:	^(I_LABEL label address)
		{
			String labelName = $label.labelName;
			if ($method::labels.containsKey(labelName)) {
				throw new SemanticException(input, "Label " + labelName + " has multiple defintions.");
			}
				
			
			$method::labels.put(labelName, $address.address);
		};
	
catches	:	^(I_CATCHES catch_directive*);

catch_directive
	:	^(I_CATCH address nonvoid_type_descriptor from=offset_or_label_absolute[$address.address] to=offset_or_label_absolute[$address.address] using=offset_or_label_absolute[$address.address])
		{
			TypeIdItem type = $nonvoid_type_descriptor.type;
			int startAddress = $from.address;
			int endAddress = $to.address;
			int handlerAddress = $using.address;

			$method::tryList.addHandler(type, startAddress, endAddress, handlerAddress);
		};
		
address returns[int address]
	:	I_ADDRESS
		{
			$address = Integer.parseInt($I_ADDRESS.text);	
		};

parameters returns[AnnotationSetRefList parameterAnnotations]
	@init
	{
		int parameterCount = 0;
		List<AnnotationSetItem> annotationSetItems = new ArrayList<AnnotationSetItem>();
	}
	:	^(I_PARAMETERS	(parameter
				{
					if ($parameter.parameterAnnotationSet != null) {
						while (annotationSetItems.size() < parameterCount) {
							annotationSetItems.add(new AnnotationSetItem(dexFile, -1));
						}
						annotationSetItems.add($parameter.parameterAnnotationSet);
					}
					
					parameterCount++;					
				})*
		)
		{
			if (annotationSetItems.size() > 0) {
				while (annotationSetItems.size() < parameterCount) {
					annotationSetItems.add(new AnnotationSetItem(dexFile, -1));
				}
				$parameterAnnotations = new AnnotationSetRefList(dexFile, annotationSetItems);
			}
		};
	
parameter returns[AnnotationSetItem parameterAnnotationSet]
	:	^(I_PARAMETER 	(	string_literal {$method::debugInfo.addParameterName($string_literal.value);}
				|	I_PARAMETER_NOT_SPECIFIED {$method::debugInfo.addParameterName(null);}
				)
				annotations {$parameterAnnotationSet = $annotations.annotationSetItem;}
		);

ordered_debug_directives[int totalMethodRegisters, int methodParameterRegisters]
	:	^(I_ORDERED_DEBUG_DIRECTIVES 	(	line
						| 	local[$totalMethodRegisters, $methodParameterRegisters]
						|	end_local[$totalMethodRegisters, $methodParameterRegisters]
						|	restart_local[$totalMethodRegisters, $methodParameterRegisters]
						|	prologue
						|	epilogue
						|	source
						)*);
		
line
	:	^(I_LINE integral_literal address)
		{
			$method::debugInfo.addLine($address.address, $integral_literal.value); 
		};

local[int totalMethodRegisters, int methodParameterRegisters]
	:	^(I_LOCAL REGISTER SIMPLE_NAME nonvoid_type_descriptor string_literal? address)
		{
			int registerNumber = parseRegister_short($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
			
			if ($string_literal.value != null) {
				$method::debugInfo.addLocalExtended($address.address, registerNumber, $SIMPLE_NAME.text, $nonvoid_type_descriptor.type.getTypeDescriptor(), $string_literal.value);
			} else {	
				$method::debugInfo.addLocal($address.address, registerNumber, $SIMPLE_NAME.text, $nonvoid_type_descriptor.type.getTypeDescriptor());
			}
		};

end_local[int totalMethodRegisters, int methodParameterRegisters]
	:	^(I_END_LOCAL REGISTER address)
		{
			int registerNumber = parseRegister_short($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
			
			$method::debugInfo.addEndLocal($address.address, registerNumber);
		};

restart_local[int totalMethodRegisters, int methodParameterRegisters]
	:	^(I_RESTART_LOCAL REGISTER address)
		{
			int registerNumber = parseRegister_short($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
			
			$method::debugInfo.addRestartLocal($address.address, registerNumber);
		};
		
prologue
	:	^(I_PROLOGUE address)
		{
			$method::debugInfo.addPrologue($address.address);
		};

epilogue
	:	^(I_EPILOGUE address)
		{
			$method::debugInfo.addEpilogue($address.address);
		};

source
	:	^(I_SOURCE string_literal address)
		{
			$method::debugInfo.addSetFile($address.address, $string_literal.value);
		};

statements[int totalMethodRegisters, int methodParameterRegisters] returns[ArrayList<InstructionField> instructions]
	@init
	{
		$instructions = new ArrayList<InstructionField>();
	}
	:	^(I_STATEMENTS	(instruction[$totalMethodRegisters, $methodParameterRegisters]
				{
					if ($instruction.instruction != null) {
						$instructions.add($instruction.instruction);
						$method::currentAddress += $instruction.instruction.getSize($method::currentAddress) / 2;
					}
				})*);
			
label_ref returns[int labelAddress]
	:	label
		{
			String labelName = $label.labelName;
			
			Integer labelAdd = $method::labels.get(labelName);
			
			if (labelAdd == null) {
				throw new SemanticException(input, "Label \"" + labelName + "\" is not defined.");
			}
			
			$labelAddress = labelAdd;
		};
	
	
label returns[String labelName]
	:	LABEL
		{
			String label = $LABEL.text;
			return label.substring(0, label.length()-1);
		};
		
offset	returns[int offsetValue]
	:	OFFSET
		{
			String offsetText = $OFFSET.text;
			$offsetValue = literalTools.parseInt(offsetText);
		};
		
offset_or_label_absolute[int baseAddress] returns[int address]
	:	offset {$address = $offset.offsetValue + $baseAddress;}
	|	label_ref {$address = $label_ref.labelAddress;};

offset_or_label returns[int offsetValue]
	:	offset {$offsetValue = $offset.offsetValue;}
	|	label_ref {$offsetValue = $label_ref.labelAddress-$method::currentAddress;};
	
instruction[int totalMethodRegisters, int methodParameterRegisters]  returns[InstructionField instruction]
	:	//e.g. goto endloop:
		^(I_STATEMENT_FORMAT10t INSTRUCTION_FORMAT10t offset_or_label)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT10t.text);
			
			int addressOffset = $offset_or_label.offsetValue;

			if (addressOffset < Byte.MIN_VALUE || addressOffset > Byte.MAX_VALUE) {
				throw new SemanticException(input, "The offset/label is out of range. The offset is " + Integer.toString(addressOffset) + " and the range for this opcode is [-128, 127].");
			}
			
			$instruction = new InstructionField(dexFile, new Instruction10t(dexFile, opcode, (byte)addressOffset));
		}
	|	//e.g. return
		^(I_STATEMENT_FORMAT10x INSTRUCTION_FORMAT10x)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT10x.text);
			$instruction = new InstructionField(dexFile, new Instruction10x(dexFile, opcode));
		}
	|	//e.g. const/4 v0, 5
		^(I_STATEMENT_FORMAT11n INSTRUCTION_FORMAT11n REGISTER short_integral_literal)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT11n.text);
			byte regA = parseRegister_nibble($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);

			short litB = $short_integral_literal.value;
			literalTools.checkNibble(litB);
			
			$instruction = new InstructionField(dexFile, new Instruction11n(dexFile, opcode, regA, (byte)litB));
		}				
	|	//e.g. move-result-object v1
		^(I_STATEMENT_FORMAT11x INSTRUCTION_FORMAT11x REGISTER)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT11x.text);
			short regA = parseRegister_byte($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
			
			$instruction = new InstructionField(dexFile, new Instruction11x(dexFile, opcode, regA));
		}
	|	//e.g. move v1 v2
		^(I_STATEMENT_FORMAT12x INSTRUCTION_FORMAT12x registerA=REGISTER registerB=REGISTER)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT12x.text);
			byte regA = parseRegister_nibble($registerA.text, $totalMethodRegisters, $methodParameterRegisters);
			byte regB = parseRegister_nibble($registerB.text, $totalMethodRegisters, $methodParameterRegisters);
			
			$instruction = new InstructionField(dexFile, new Instruction12x(dexFile, opcode, regA, regB));
		}
	|	//e.g. goto/16 endloop:
		^(I_STATEMENT_FORMAT20t INSTRUCTION_FORMAT20t offset_or_label)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT20t.text);
			
			int addressOffset = $offset_or_label.offsetValue;

			if (addressOffset < Short.MIN_VALUE || addressOffset > Short.MAX_VALUE) {
				throw new SemanticException(input, "The offset/label is out of range. The offset is " + Integer.toString(addressOffset) + " and the range for this opcode is [-32768, 32767].");
			}
			
			$instruction = new InstructionField(dexFile, new Instruction20t(dexFile, opcode, (short)addressOffset));
		}
	|	//e.g. sget_object v0 java/lang/System/out LJava/io/PrintStream;
		^(I_STATEMENT_FORMAT21c_FIELD INSTRUCTION_FORMAT21c_FIELD REGISTER fully_qualified_field)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT21c_FIELD.text);
			short regA = parseRegister_byte($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
			
			FieldIdItem fieldIdItem = $fully_qualified_field.fieldIdItem;

			$instruction = new InstructionField(dexFile, new Instruction21c(dexFile, opcode, regA, fieldIdItem));
		}
	|	//e.g. const-string v1 "Hello World!"
		^(I_STATEMENT_FORMAT21c_STRING INSTRUCTION_FORMAT21c_STRING REGISTER string_literal)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT21c_STRING.text);
			short regA = parseRegister_byte($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
			
			StringIdItem stringIdItem = new StringIdItem(dexFile, $string_literal.value);

			$instruction = new InstructionField(dexFile, new Instruction21c(dexFile, opcode, regA, stringIdItem));
		}
	|	//e.g. const-class v2 org/jf/HelloWorld2/HelloWorld2
		^(I_STATEMENT_FORMAT21c_TYPE INSTRUCTION_FORMAT21c_TYPE REGISTER reference_type_descriptor)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT21c_TYPE.text);
			short regA = parseRegister_byte($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
			
			TypeIdItem typeIdItem = $reference_type_descriptor.type;
			
			$instruction = new InstructionField(dexFile, new Instruction21c(dexFile, opcode, regA, typeIdItem));
		}
	|	//e.g. const/high16 v1, 1234
		^(I_STATEMENT_FORMAT21h INSTRUCTION_FORMAT21h REGISTER short_integral_literal)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT21h.text);
			short regA = parseRegister_byte($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
			
			short litB = $short_integral_literal.value;
			
			$instruction = new InstructionField(dexFile, new Instruction21h(dexFile, opcode, regA, litB));
		}
	|	//e.g. const/16 v1, 1234
		^(I_STATEMENT_FORMAT21s INSTRUCTION_FORMAT21s REGISTER short_integral_literal)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT21s.text);
			short regA = parseRegister_byte($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
			
			short litB = $short_integral_literal.value;
			
			$instruction = new InstructionField(dexFile, new Instruction21s(dexFile, opcode, regA, litB));
		}
	|	//e.g. if-eqz v0, endloop:
		^(I_STATEMENT_FORMAT21t INSTRUCTION_FORMAT21t REGISTER offset_or_label)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT21t.text);
			short regA = parseRegister_byte($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
			
			int addressOffset = $offset_or_label.offsetValue;

			if (addressOffset < Short.MIN_VALUE || addressOffset > Short.MAX_VALUE) {
				throw new SemanticException(input, "The offset/label is out of range. The offset is " + Integer.toString(addressOffset) + " and the range for this opcode is [-32768, 32767].");
			}
			
			$instruction = new InstructionField(dexFile, new Instruction21t(dexFile, opcode, regA, (short)addressOffset));
		}
	|	//e.g. add-int v0, v1, 123
		^(I_STATEMENT_FORMAT22b INSTRUCTION_FORMAT22b registerA=REGISTER registerB=REGISTER short_integral_literal)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT22b.text);
			short regA = parseRegister_byte($registerA.text, $totalMethodRegisters, $methodParameterRegisters);
			short regB = parseRegister_byte($registerB.text, $totalMethodRegisters, $methodParameterRegisters);
			
			short litC = $short_integral_literal.value;
			literalTools.checkByte(litC);
			
			$instruction = new InstructionField(dexFile, new Instruction22b(dexFile, opcode, regA, regB, (byte)litC));
		}
	|	//e.g. iput-object v1 v0 org/jf/HelloWorld2/HelloWorld2.helloWorld Ljava/lang/String;
		^(I_STATEMENT_FORMAT22c_FIELD INSTRUCTION_FORMAT22c_FIELD registerA=REGISTER registerB=REGISTER fully_qualified_field)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT22c_FIELD.text);
			byte regA = parseRegister_nibble($registerA.text, $totalMethodRegisters, $methodParameterRegisters);
			byte regB = parseRegister_nibble($registerB.text, $totalMethodRegisters, $methodParameterRegisters);
			
			FieldIdItem fieldIdItem = $fully_qualified_field.fieldIdItem;
			
			$instruction = new InstructionField(dexFile, new Instruction22c(dexFile, opcode, regA, regB, fieldIdItem));
		}
	|	//e.g. instance-of v0, v1, Ljava/lang/String;
		^(I_STATEMENT_FORMAT22c_TYPE INSTRUCTION_FORMAT22c_TYPE registerA=REGISTER registerB=REGISTER nonvoid_type_descriptor)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT22c_TYPE.text);
			byte regA = parseRegister_nibble($registerA.text, $totalMethodRegisters, $methodParameterRegisters);
			byte regB = parseRegister_nibble($registerB.text, $totalMethodRegisters, $methodParameterRegisters);
			
			TypeIdItem typeIdItem = $nonvoid_type_descriptor.type;
			
			$instruction = new InstructionField(dexFile, new Instruction22c(dexFile, opcode, regA, regB, typeIdItem));
		}
	|	//e.g. add-int/lit16 v0, v1, 12345
		^(I_STATEMENT_FORMAT22s INSTRUCTION_FORMAT22s registerA=REGISTER registerB=REGISTER short_integral_literal)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT22s.text);
			byte regA = parseRegister_nibble($registerA.text, $totalMethodRegisters, $methodParameterRegisters);
			byte regB = parseRegister_nibble($registerB.text, $totalMethodRegisters, $methodParameterRegisters);
			
			short litC = $short_integral_literal.value;
			
			$instruction = new InstructionField(dexFile, new Instruction22s(dexFile, opcode, regA, regB, litC));
		}
	|	//e.g. if-eq v0, v1, endloop:
		^(I_STATEMENT_FORMAT22t INSTRUCTION_FORMAT22t registerA=REGISTER registerB=REGISTER offset_or_label)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT22t.text);
			byte regA = parseRegister_nibble($registerA.text, $totalMethodRegisters, $methodParameterRegisters);
			byte regB = parseRegister_nibble($registerB.text, $totalMethodRegisters, $methodParameterRegisters);
			
			int addressOffset = $offset_or_label.offsetValue;

			if (addressOffset < Short.MIN_VALUE || addressOffset > Short.MAX_VALUE) {
				throw new SemanticException(input, "The offset/label is out of range. The offset is " + Integer.toString(addressOffset) + " and the range for this opcode is [-32768, 32767].");
			}
			
			$instruction = new InstructionField(dexFile, new Instruction22t(dexFile, opcode, regA, regB, (short)addressOffset));
		}
	|	//e.g. move/from16 v1, v1234
		^(I_STATEMENT_FORMAT22x INSTRUCTION_FORMAT22x registerA=REGISTER registerB=REGISTER)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT22x.text);
			short regA = parseRegister_byte($registerA.text, $totalMethodRegisters, $methodParameterRegisters);
			int regB = parseRegister_short($registerB.text, $totalMethodRegisters, $methodParameterRegisters);
			
			$instruction = new InstructionField(dexFile, new Instruction22x(dexFile, opcode, regA, regB));
		}
	|	//e.g. add-int v1, v2, v3
		^(I_STATEMENT_FORMAT23x INSTRUCTION_FORMAT23x registerA=REGISTER registerB=REGISTER registerC=REGISTER)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT23x.text);
			short regA = parseRegister_byte($registerA.text, $totalMethodRegisters, $methodParameterRegisters);
			short regB = parseRegister_byte($registerB.text, $totalMethodRegisters, $methodParameterRegisters);
			short regC = parseRegister_byte($registerC.text, $totalMethodRegisters, $methodParameterRegisters);			
			
			$instruction = new InstructionField(dexFile, new Instruction23x(dexFile, opcode, regA, regB, regC));
		}
	|	//e.g. goto/32 endloop:
		^(I_STATEMENT_FORMAT30t INSTRUCTION_FORMAT30t offset_or_label)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT30t.text);
			
			int addressOffset = $offset_or_label.offsetValue;
	
			$instruction = new InstructionField(dexFile, new Instruction30t(dexFile, opcode, addressOffset));
		}
	|	//e.g. const-string/jumbo v1 "Hello World!"
		^(I_STATEMENT_FORMAT31c INSTRUCTION_FORMAT31c REGISTER string_literal)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT31c.text);
			short regA = parseRegister_byte($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
					
			StringIdItem stringIdItem = new StringIdItem(dexFile, $string_literal.value);
			
			$instruction = new InstructionField(dexFile, new Instruction31c(dexFile, opcode, regA, stringIdItem));
		}
	|	//e.g. const v0, 123456
		^(I_STATEMENT_FORMAT31i INSTRUCTION_FORMAT31i REGISTER fixed_32bit_literal)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT31i.text);
			short regA = parseRegister_byte($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
			
			int litB = $fixed_32bit_literal.value;
			
			$instruction = new InstructionField(dexFile, new Instruction31i(dexFile, opcode, regA, litB));
		}
	|	//e.g. fill-array-data v0, ArrayData:
		^(I_STATEMENT_FORMAT31t INSTRUCTION_FORMAT31t REGISTER offset_or_label)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT31t.text);
			
			short regA = parseRegister_byte($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
			
			int addressOffset = $offset_or_label.offsetValue;
			if (($method::currentAddress + addressOffset) \% 2 != 0) {
				addressOffset++;
			}
			
			$instruction = new InstructionField(dexFile, new Instruction31t(dexFile, opcode, regA, addressOffset));
		}
	|	//e.g. move/16 v5678, v1234
		^(I_STATEMENT_FORMAT32x INSTRUCTION_FORMAT32x registerA=REGISTER registerB=REGISTER)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT32x.text);
			int regA = parseRegister_short($registerA.text, $totalMethodRegisters, $methodParameterRegisters);
			int regB = parseRegister_short($registerB.text, $totalMethodRegisters, $methodParameterRegisters);
			
			$instruction = new InstructionField(dexFile, new Instruction32x(dexFile, opcode, regA, regB));
		}
	|	//e.g. invoke-virtual {v0,v1} java/io/PrintStream/print(Ljava/lang/Stream;)V
		^(I_STATEMENT_FORMAT35c_METHOD INSTRUCTION_FORMAT35c_METHOD register_list[$totalMethodRegisters, $methodParameterRegisters] fully_qualified_method)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT35c_METHOD.text);

			//this depends on the fact that register_list returns a byte[5]
			byte[] registers = $register_list.registers;
			byte registerCount = $register_list.registerCount;
			
			MethodIdItem methodIdItem = $fully_qualified_method.methodIdItem;
			
			$instruction = new InstructionField(dexFile, new Instruction35c(dexFile, opcode, registerCount, registers[0], registers[1], registers[2], registers[3], registers[4], methodIdItem));
		}
	|	//e.g. filled-new-array {v0,v1}, I
		^(I_STATEMENT_FORMAT35c_TYPE INSTRUCTION_FORMAT35c_TYPE register_list[$totalMethodRegisters, $methodParameterRegisters] nonvoid_type_descriptor)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT35c_TYPE.text);

			//this depends on the fact that register_list returns a byte[5]
			byte[] registers = $register_list.registers;
			byte registerCount = $register_list.registerCount;
			
			TypeIdItem typeIdItem = $nonvoid_type_descriptor.type;
			
			$instruction = new InstructionField(dexFile, new Instruction35c(dexFile, opcode, registerCount, registers[0], registers[1], registers[2], registers[3], registers[4], typeIdItem));
		}
	|	//e.g. invoke-virtual/range {v25..v26} java/lang/StringBuilder/append(Ljava/lang/String;)Ljava/lang/StringBuilder;
		^(I_STATEMENT_FORMAT3rc_METHOD INSTRUCTION_FORMAT3rc_METHOD register_range[$totalMethodRegisters, $methodParameterRegisters] fully_qualified_method)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT3rc_METHOD.text);
			int startRegister = $register_range.startRegister;
			int endRegister = $register_range.endRegister;
			
			int registerCount = endRegister-startRegister+1;
			if (registerCount > 256) {
				throw new SemanticException(input, "A register range can span a maximum of 256 registers");
			}
			if (registerCount < 1) {
				throw new SemanticException(input, "A register range must have the lower register listed first");
			}
			
			MethodIdItem methodIdItem = $fully_qualified_method.methodIdItem;

			//not supported yet
			$instruction = new InstructionField(dexFile, new Instruction3rc(dexFile, opcode, (short)registerCount, startRegister, methodIdItem));
		}
	|	//e.g. filled-new-array/range {v0..v6} I
		^(I_STATEMENT_FORMAT3rc_TYPE INSTRUCTION_FORMAT3rc_TYPE register_range[$totalMethodRegisters, $methodParameterRegisters] nonvoid_type_descriptor)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT3rc_TYPE.text);
			int startRegister = $register_range.startRegister;
			int endRegister = $register_range.endRegister;
			
			int registerCount = endRegister-startRegister+1;
			if (registerCount > 256) {
				throw new SemanticException(input, "A register range can span a maximum of 256 registers");
			}
			if (registerCount < 1) {
				throw new SemanticException(input, "A register range must have the lower register listed first");
			}
			
			TypeIdItem typeIdItem = $nonvoid_type_descriptor.type;

			//not supported yet
			$instruction = new InstructionField(dexFile, new Instruction3rc(dexFile, opcode, (short)registerCount, startRegister, typeIdItem));
		}	
	|	//e.g. const-wide v0, 5000000000L
		^(I_STATEMENT_FORMAT51l INSTRUCTION_FORMAT51l REGISTER fixed_64bit_literal)
		{
			Opcode opcode = Opcode.getOpcodeByName($INSTRUCTION_FORMAT51l.text);
			short regA = parseRegister_byte($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
			
			long litB = $fixed_64bit_literal.value;
			
			$instruction = new InstructionField(dexFile, new Instruction51l(dexFile, opcode, regA, litB));		
		}
	|	//e.g. .array-data 4 1000000 .end array-data
		^(I_STATEMENT_ARRAY_DATA ^(I_ARRAY_ELEMENT_SIZE short_integral_literal) array_elements)
		{
			int elementWidth = $short_integral_literal.value;
			List<byte[]> byteValues = $array_elements.values;
			
			$instruction = new InstructionField(dexFile, new ArrayDataPseudoInstruction(dexFile, elementWidth, byteValues));
		}
	|
		
		^(I_STATEMENT_PACKED_SWITCH ^(I_PACKED_SWITCH_BASE_OFFSET base_offset=offset_or_label) ^(I_PACKED_SWITCH_START_KEY fixed_32bit_literal) packed_switch_targets[$base_offset.offsetValue])
		{
			int startKey = $fixed_32bit_literal.value;
			int[] targets = $packed_switch_targets.targets;
			
			$instruction = new InstructionField(dexFile, new PackedSwitchDataPseudoInstruction(dexFile, startKey, targets));
		}
	|
		^(I_STATEMENT_SPARSE_SWITCH ^(I_SPARSE_SWITCH_BASE_OFFSET base_offset=offset_or_label) sparse_switch_target_count sparse_switch_keys[$sparse_switch_target_count.targetCount] sparse_switch_targets[$base_offset.offsetValue, $sparse_switch_target_count.targetCount])
		{
			int[] keys = $sparse_switch_keys.keys;
			int[] targets = $sparse_switch_targets.targets;
			
			$instruction = new InstructionField(dexFile, new SparseSwitchDataPseudoInstruction(dexFile, keys, targets));
		};
		catch [Exception ex] {
			reportError(new SemanticException(input, ex));
			recover(input, null);
		}


register_list[int totalMethodRegisters, int methodParameterRegisters] returns[byte[\] registers, byte registerCount]
	@init
	{
		$registers = new byte[5];
		$registerCount = 0;
	}
	:	^(I_REGISTER_LIST 
			(REGISTER
			{
				if ($registerCount == 5) {
					throw new SemanticException(input, "A list of registers can only have a maximum of 5 registers. Use the <op>/range alternate opcode instead.");
				}
				$registers[$registerCount++] = parseRegister_nibble($REGISTER.text, $totalMethodRegisters, $methodParameterRegisters);
			})*);
	
register_range[int totalMethodRegisters, int methodParameterRegisters] returns[int startRegister, int endRegister]
	:	^(I_REGISTER_RANGE startReg=REGISTER endReg=REGISTER?)
		{
			$startRegister  = parseRegister_short($startReg.text, $totalMethodRegisters, $methodParameterRegisters);
			if ($endReg == null) {
				$endRegister = $startRegister;
			} else {
				$endRegister = parseRegister_short($endReg.text, $totalMethodRegisters, $methodParameterRegisters);
			}
		}
	;

nonvoid_type_descriptor returns [TypeIdItem type]
	:	(PRIMITIVE_TYPE
	|	CLASS_DESCRIPTOR	
	|	ARRAY_DESCRIPTOR)
	{
		$type = new TypeIdItem(dexFile, $start.getText());
	};
	
reference_type_descriptor returns [TypeIdItem type]
	:	(CLASS_DESCRIPTOR
	|	ARRAY_DESCRIPTOR)
	{
		$type = new TypeIdItem(dexFile, $start.getText());
	};

class_type_descriptor returns [TypeIdItem type]
	:	CLASS_DESCRIPTOR
	{
		$type = new TypeIdItem(dexFile, $CLASS_DESCRIPTOR.text);
	};

type_descriptor returns [TypeIdItem type]
	:	VOID_TYPE {$type = new TypeIdItem(dexFile, "V");}
	|	nonvoid_type_descriptor {$type = $nonvoid_type_descriptor.type;}
	;
	
short_integral_literal returns[short value]
	:	long_literal
		{
			literalTools.checkShort($long_literal.value);
			$value = (short)$long_literal.value;
		}
	|	integer_literal
		{
			literalTools.checkShort($integer_literal.value);
			$value = (short)$integer_literal.value;
		}
	|	short_literal {$value = $short_literal.value;}
	|	char_literal {$value = (short)$char_literal.value;}
	|	byte_literal {$value = $byte_literal.value;};
	
integral_literal returns[int value]
	:	long_literal
		{
			literalTools.checkInt($long_literal.value);
			$value = (short)$long_literal.value;
		}
	|	integer_literal {$value = (short)$integer_literal.value;}
	|	short_literal {$value = $short_literal.value;}
	|	byte_literal {$value = $byte_literal.value;};
		
	
integer_literal returns[int value]
	:	INTEGER_LITERAL { $value = literalTools.parseInt($INTEGER_LITERAL.text); };

long_literal returns[long value]
	:	LONG_LITERAL { $value = literalTools.parseLong($LONG_LITERAL.text); };

short_literal returns[short value]
	:	SHORT_LITERAL { $value = literalTools.parseShort($SHORT_LITERAL.text); };

byte_literal returns[byte value]
	:	BYTE_LITERAL { $value = literalTools.parseByte($BYTE_LITERAL.text); };
	
float_literal returns[float value]
	:	FLOAT_LITERAL { $value = Float.parseFloat($FLOAT_LITERAL.text); };
	
double_literal returns[double value]
	:	DOUBLE_LITERAL { $value = Double.parseDouble($DOUBLE_LITERAL.text); };

char_literal returns[char value]
	:	CHAR_LITERAL { $value = $CHAR_LITERAL.text.charAt(1); };

string_literal returns[String value]
	:	STRING_LITERAL
		{
			$value = $STRING_LITERAL.text;
			$value = $value.substring(1,$value.length()-1);
		};

bool_literal returns[boolean value]
	:	BOOL_LITERAL { $value = Boolean.parseBoolean($BOOL_LITERAL.text); };

array_literal returns[ArrayList<EncodedValue> values]
	:	{$values = new ArrayList<EncodedValue>();}
		^(I_ENCODED_ARRAY (literal {$values.add($literal.encodedValue);})*);


annotations returns[AnnotationSetItem annotationSetItem]
	:	{ArrayList<AnnotationItem> annotationList = new ArrayList<AnnotationItem>();}
		^(I_ANNOTATIONS (annotation {annotationList.add($annotation.annotationItem);} )*)
		{
			if (annotationList.size() > 0) {
				$annotationSetItem = new AnnotationSetItem(dexFile, annotationList);
			}
		};
		

annotation returns[AnnotationItem annotationItem]
	:	^(I_ANNOTATION ANNOTATION_VISIBILITY subannotation)
		{
			AnnotationVisibility visibility = AnnotationVisibility.fromName($ANNOTATION_VISIBILITY.text);
			$annotationItem = new AnnotationItem(dexFile, visibility, $subannotation.value);
		};

annotation_element returns[AnnotationElement element]
	:	^(I_ANNOTATION_ELEMENT MEMBER_NAME literal)
		{
			$element = new AnnotationElement(dexFile, new StringIdItem(dexFile, $MEMBER_NAME.text), $literal.encodedValue);
		};

subannotation returns[AnnotationEncodedValueSubField value]
	:	{ArrayList<AnnotationElement> elements = new ArrayList<AnnotationElement>();}
		^(	I_SUBANNOTATION
			class_type_descriptor
			(annotation_element {elements.add($annotation_element.element);} )* )
		{
			$value = new AnnotationEncodedValueSubField(dexFile, $class_type_descriptor.type, elements);
		};

field_literal returns[EncodedIndexedItemReference<FieldIdItem> value]
	:	^(I_ENCODED_FIELD fully_qualified_field)
		{
			$value = new EncodedIndexedItemReference<FieldIdItem>(dexFile, $fully_qualified_field.fieldIdItem);
		};

method_literal returns[EncodedIndexedItemReference<MethodIdItem> value]
	:	^(I_ENCODED_METHOD fully_qualified_method)
		{
			$value = new EncodedIndexedItemReference<MethodIdItem>(dexFile, $fully_qualified_method.methodIdItem);
		};

enum_literal returns[EncodedIndexedItemReference<FieldIdItem> value]
	:	^(I_ENCODED_ENUM fully_qualified_field)
		{
			$value = new EncodedIndexedItemReference<FieldIdItem>(dexFile, $fully_qualified_field.fieldIdItem, true);
		};