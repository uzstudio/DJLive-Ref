//
// MTSourcePlayer.m
//
// AD5RX Morse Trainer
// Copyright (c) 2008 Jon Nall
// All rights reserved.
//
// LICENSE
// This file is part of AD5RX Morse Trainer.
// 
// AD5RX Morse Trainer is free software: you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
// 
// AD5RX Morse Trainer is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with AD5RX Morse Trainer.  If not, see <http://www.gnu.org/licenses/>.




#import "MTOperationQueue.h"
#import "MTSourcePlayer.h"
#include "MTDefines.h"

#include "../CoreAudioUtilityClasses/CoreAudio/PublicUtility/CAAudioBufferList.h"

FILE* pcm_dump = NULL;

void sourcePlayerCompleteProc(void* arg, ScheduledAudioSlice* slice)
{
	static NSUInteger count = 0;
	++count;
    
	MTSourcePlayer* player = (__bridge MTSourcePlayer *)(arg);

	// NSLog(@"%@: completionCallback for offset %f", [player name], slice->mTimeStamp.mSampleTime);
	if(slice->mFlags & kScheduledAudioSliceFlag_BeganToRenderLate)
	{
		NSLog(@"WARNING: Late render on %@", [player name]);
	}
	
	[player sliceCompleted:slice];
}

@interface MTSourcePlayer (Private)
-(NSUInteger)scheduleSlices;
-(void)invokeTextTrackingCallback:(NSString*)theText;
@end

@implementation MTSourcePlayer

-(id)initWithAU:(AudioUnit)theUnit
{
	unit = theUnit;
	offset = 0;
	
	enabled = NO;
	
	
	slicesInProgress = 0;
	
	sliceRing = (struct ScheduledAudioSlice*)calloc(kNumSlices, sizeof(struct ScheduledAudioSlice));
	bzero(sliceRing, sizeof(struct ScheduledAudioSlice) * kNumSlices);
	
	AudioTimeStamp timestamp;
	bzero(&timestamp, sizeof(timestamp));
	timestamp.mFlags = kAudioTimeStampSampleTimeValid;
	timestamp.mSampleTime = -1.; // Play immediately
	
    for(NSUInteger s = 0; s < kNumSlices; ++s)
    {
        sliceRing[s].mTimeStamp = timestamp;
        sliceRing[s].mCompletionProc = sourcePlayerCompleteProc;
        sliceRing[s].mCompletionProcUserData = (__bridge void *)(self);
        
        sliceRing[s].mNumberFrames = kMaxFrameSize;
        sliceRing[s].mFlags = kScheduledAudioSliceFlag_Complete;
        sliceRing[s].mReserved = 0;
        
        AudioBufferList *bufferList = NULL;
#if 0   // mono
        bufferList = CAAudioBufferList::Create(1);
        
        bufferList->mBuffers[0].mData = malloc(kMaxFrameSize*sizeof(AudioUnitSampleType));
        bufferList->mBuffers[0].mDataByteSize = kMaxFrameSize*sizeof(AudioUnitSampleType);
        bufferList->mBuffers[0].mNumberChannels = 1;//streamFormat.mChannelsPerFrame;
#else   // stereo
        bufferList = CAAudioBufferList::Create(2/*streamFormat.mChannelsPerFrame*/);
        
        for (UInt32 index = 0; index < bufferList->mNumberBuffers; index++)
        {
            bufferList->mBuffers[index].mData = malloc(kMaxFrameSize*sizeof(AudioUnitSampleType));
            bufferList->mBuffers[index].mDataByteSize = kMaxFrameSize*sizeof(AudioUnitSampleType);
            bufferList->mBuffers[index].mNumberChannels = 1;
        }
#endif
        sliceRing[s].mBufferList = bufferList;
    }
    
    NSString *res_path = [[NSBundle mainBundle] resourcePath];
    
    NSMutableString *str=[NSMutableString stringWithString:res_path];
    [str appendString:@"/raw.pcm"];
    
    pcm_dump = fopen([str UTF8String], "rb");
	
	return self;
}

-(void)dealloc
{
	if(sliceRing != nil)
	{
		for(int s = 0; s < kNumSlices; ++s)
		{
			for(int b = 0; b < sliceRing[s].mBufferList->mNumberBuffers; ++b)
			{
				free(sliceRing[s].mBufferList->mBuffers[b].mData);
			}
		}
        
		free(sliceRing);
		sliceRing = nil;
	}
}

-(void)setSource:(id<MTSoundSource>)theSource
{
	source = theSource;
}

-(void)setEnabled:(BOOL)isEnabled
{
	enabled = isEnabled;
}

-(BOOL)enabled
{
	return enabled;
}

-(NSString*)name
{
	return [source name];
}

-(void)sliceCompleted:(ScheduledAudioSlice*)theSlice;
{
	--slicesInProgress;
	
	if([source supportsTextTracking])
	{
		NSString* text = [source getTextForTime:theSlice->mTimeStamp.mSampleTime];
		if([text length] > 0)
		{
			NSInvocationOperation* theOp = [[NSInvocationOperation alloc]
											initWithTarget:self
											selector:@selector(invokeTextTrackingCallback:)
											object:text];	
			
			[[MTOperationQueue operationQueue] addOperation:theOp];
		}		
	}
	
    if(slicesInProgress == 0)
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotifSoundPlayerComplete object:self];
    }
    
    
	// If player becomes disabled, don't schedule any more
	if([self enabled])
	{
		[self scheduleSlices];
	}    
}


-(void)reset
{
    [source reset];
}

static void CheckError(OSStatus error, const char *operation)
{
    if (error == noErr) return;
    
    char str[20];
    // see if it appears to be a 4-char-code
    *(UInt32 *)(str + 1) = CFSwapInt32HostToBig(error);
    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
        str[0] = str[5] = '\'';
        str[6] = '\0';
    } else {
        // no, format it as an integer
        sprintf(str, "%d", (int)error);
    }
    
    fprintf(stderr, "Error: %s (%s)\n", operation, str);
}

-(void)start
{
	if(![self enabled])
	{
		return;
	}
	
	AudioTimeStamp timestamp;
	bzero(&timestamp, sizeof(timestamp));
	timestamp.mFlags = kAudioTimeStampSampleTimeValid;
	timestamp.mSampleTime = -1.; // Play immediately
	
	OSStatus err = noErr;
	err = AudioUnitSetProperty(unit, kAudioUnitProperty_ScheduleStartTimeStamp,
							   kAudioUnitScope_Global, 0, &timestamp, sizeof(timestamp));
	if(err != noErr)
	{
        CheckError(err, "");
	}
	else
	{
		NSUInteger scheduledSlices = 0;
		do
		{
			scheduledSlices = [self scheduleSlices];
		}
		while(scheduledSlices == 0);
	}
}

-(void)stop
{
	[self setEnabled:NO];
	offset = 0;
	OSStatus err = AudioUnitReset(unit, kAudioUnitScope_Global, 0);
	if(err != noErr)
	{
		NSLog(@"ERROR: Couldn't reset audio unit");
	}
}
@end

@implementation MTSourcePlayer (Private)

-(NSUInteger)scheduleSlices
{
    if (pcm_dump == NULL)
        return 0;
    
	// Iterate through the slices and find any that are free. Fill those with
	// data from our data, schedule them, and update our bookkeeping.
    
	int freeSlices = 0;
	int scheduledSlices = 0;
	for(NSUInteger s = 0; s < kNumSlices; ++s)
	{
		if(!(sliceRing[s].mFlags & kScheduledAudioSliceFlag_Complete))
		{
			// Don't bother with slices that still need to be played
			continue;
		}
		
		++freeSlices;
        
        float pcm_buff[512 * 2] = {0};
        fread(pcm_buff, 4, kMaxFrameSize * 2, pcm_dump);
        for ( int i=0; i < sliceRing[s].mBufferList->mNumberBuffers; i++ ) {
            sliceRing[s].mBufferList->mBuffers[i].mDataByteSize = (kMaxFrameSize * sizeof(float));
            
            if (i == 0) {
                for (int j = 0; j < kMaxFrameSize; j++) {
                    memcpy((float*)(sliceRing[s].mBufferList->mBuffers[i].mData) + j, pcm_buff + (2 * j), 4);
                }
            } else {
                for (int j = 0; j < kMaxFrameSize; j++) {
                    memcpy((float*)(sliceRing[s].mBufferList->mBuffers[i].mData) + j, pcm_buff + (2 * j + 1), 4);
                }
            }
        }
        const NSUInteger numFrames = 512;
		if(numFrames == 0)
		{
			continue;
		}
		
		// Continue filling out slice, based on response from source
		sliceRing[s].mTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
		sliceRing[s].mTimeStamp.mSampleTime = offset;
		sliceRing[s].mNumberFrames = numFrames;
        
		offset += numFrames;
		
		++slicesInProgress;
		++scheduledSlices;
		// NSLog(@"%@: scheduled @ %d", [self name], offset);
		OSStatus err = AudioUnitSetProperty(unit,
												   kAudioUnitProperty_ScheduleAudioSlice,
												   kAudioUnitScope_Global,
												   0,
												   &(sliceRing[s]),
												   sizeof(struct ScheduledAudioSlice));
		if(err != noErr)
		{
			NSLog(@"ERROR: Can't schedule slice %ld to play", s);
			return (kNumSlices - freeSlices);
		}			
	}
	
	if(freeSlices == 0)
	{
		NSLog(@"WARNING: No free slices were available");
	}
	
	// Return the number of scheduled slices
	return scheduledSlices;
}

-(void)invokeTextTrackingCallback:(NSString*)theText
{
    if([self enabled])
    {
        NSMutableDictionary* dict = [NSMutableDictionary dictionary];
        [dict setObject:theText forKey:kNotifTextKey];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotifTextWasPlayed object: self userInfo:dict];        
    }
}

@end