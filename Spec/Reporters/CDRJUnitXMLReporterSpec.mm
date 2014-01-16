#if TARGET_OS_IPHONE
// Normally you would include this file out of the framework.  However, we're
// testing the framework here, so including the file from the framework will
// conflict with the compiler attempting to include the file from the project.
#import "SpecHelper.h"
#else
#import <Cedar/SpecHelper.h>
#endif

#import "CDRExample.h"
#import "CDRJUnitXMLReporter.h"
#import "CDRSpecFailure.h"
#import "GDataXMLNode.h"

using namespace Cedar::Matchers;

// Test class overrides actually writing XML to a file for speed and easier assertions
@interface TestCDRJUnitXMLReporter : CDRJUnitXMLReporter {
@private
    NSString *xml_;
    GDataXMLDocument *xmlDocument_;
    GDataXMLElement * xmlRootElement_;
}

@property (nonatomic, copy) NSString *xml;
@property (nonatomic, strong) GDataXMLDocument * xmlDocument;
@property (nonatomic, strong) GDataXMLElement * xmlRootElement;
@end

@implementation TestCDRJUnitXMLReporter

@synthesize xml = xml_;
@synthesize xmlDocument = xmlDocument_;
@synthesize xmlRootElement = xmlRootElement_;

- (void)dealloc {
    self.xml = nil;
    self.xmlRootElement = nil;
    self.xmlDocument = nil;
    [super dealloc];
}

- (void)writeXmlToFile:(NSString *)xmlString {
    self.xml = xmlString;
}

// Temporarily redirect stdout to avoid unnecessary output when running tests
- (void)runDidComplete {
    FILE *realStdout = stdout;
    stdout = fopen("/dev/null", "w");

    @try {
        [super runDidComplete];
    }
    @finally {
        fclose(stdout);
        stdout = realStdout;
    }

    self.xmlDocument = [[[GDataXMLDocument alloc] initWithXMLString:self.xml options:0 error:nil] autorelease];
    self.xmlRootElement = self.xmlDocument.rootElement;
}
@end


// Allow setting state for testing purposes
@interface CDRExample (SpecPrivate)
- (void)setState:(CDRExampleState)state;
@end

@implementation CDRExample (Spec)

+ (id)exampleWithText:(NSString *)text andState:(CDRExampleState)state {
    CDRExample *example = [CDRExample exampleWithText:text andBlock:^{}];
    [example setState:state];
    return example;
}
@end


SPEC_BEGIN(CDRJUnitXMLReporterSpec)

describe(@"runDidComplete", ^{
    __block TestCDRJUnitXMLReporter *reporter;

    beforeEach(^{
        reporter = [[[TestCDRJUnitXMLReporter alloc] init] autorelease];
    });

    context(@"when no specs are run", ^{
        it(@"should output a blank test suite report", ^{
            [reporter runDidComplete];
            expect(reporter.xmlDocument).to_not(be_nil);
            expect(reporter.xmlRootElement).to_not(be_nil);
            expect(reporter.xmlRootElement.name).to(equal(@"testsuite"));
        });
    });

    describe(@"each passing spec", ^{
        it(@"should be written to the XML file", ^{
            CDRExample *example1 = [CDRExample exampleWithText:@"Passing spec 1" andState:CDRExampleStatePassed];
            [reporter reportOnExample:example1];

            CDRExample *example2 = [CDRExample exampleWithText:@"Passing spec 2" andState:CDRExampleStatePassed];
            [reporter reportOnExample:example2];

            [reporter runDidComplete];
            expect(reporter.xmlDocument).to_not(be_nil);
            expect(reporter.xmlRootElement).to_not(be_nil);

            NSArray * testCases = [reporter.xmlRootElement elementsForName:@"testcase"];
            expect(testCases.count).to(equal(2));

            expect([[testCases[0] attributeForName:@"classname"] stringValue]).to(equal(@"Cedar"));
            expect([[testCases[0] attributeForName:@"name"] stringValue]).to(equal(@"Passing spec 1"));

            expect([[testCases[1] attributeForName:@"classname"] stringValue]).to(equal(@"Cedar"));
            expect([[testCases[1] attributeForName:@"name"] stringValue]).to(equal(@"Passing spec 2"));
        });

        it(@"should have its name escaped", ^{
            NSString * stringToEscape = @"Special ' characters \" should < be & escaped > ";
            CDRExample *example = [CDRExample exampleWithText:stringToEscape andState:CDRExampleStatePassed];
            [reporter reportOnExample:example];

            [reporter runDidComplete];
            GDataXMLElement * testCase = [reporter.xmlRootElement elementsForName:@"testcase"][0];
            expect([[testCase attributeForName:@"name"] stringValue]).to(equal(stringToEscape));
        });
    });

    describe(@"each failing spec", ^{
        it(@"should be written to the XML file", ^{
            CDRExample *example1 = [CDRExample exampleWithText:@"Failing spec 1" andState:CDRExampleStateFailed];
            example1.failure = [CDRSpecFailure specFailureWithReason:@"Failure reason 1"];
            [reporter reportOnExample:example1];

            CDRExample *example2 = [CDRExample exampleWithText:@"Failing spec 2" andState:CDRExampleStateFailed];
            example2.failure = [CDRSpecFailure specFailureWithReason:@"Failure reason 2"];
            [reporter reportOnExample:example2];

            [reporter runDidComplete];

            NSArray * testCases = [reporter.xmlRootElement elementsForName:@"testcase"];
            expect(testCases.count).to(equal(2));
            expect([[testCases[0] attributeForName:@"classname"] stringValue]).to(equal(@"Cedar"));
            expect([[testCases[0] attributeForName:@"name"] stringValue]).to(equal(@"Failing spec 1"));
            expect([[[testCases[0] nodesForXPath:@"failure/@type" error:nil] firstObject] stringValue]).to(equal(@"Failure"));
            expect([[[testCases[0] nodesForXPath:@"failure/text()" error:nil] firstObject] stringValue]).to(equal(@"Failure reason 1"));


            expect([[testCases[1] attributeForName:@"classname"] stringValue]).to(equal(@"Cedar"));
            expect([[testCases[1] attributeForName:@"name"] stringValue]).to(equal(@"Failing spec 2"));
            expect([[[testCases[1] nodesForXPath:@"failure/@type" error:nil] firstObject] stringValue]).to(equal(@"Failure"));
            expect([[[testCases[1] nodesForXPath:@"failure/text()" error:nil] firstObject] stringValue]).to(equal(@"Failure reason 2"));
        });

        it(@"should have its name escaped", ^{
            NSString * stringToEscape = @"Special ' characters \" should < be & escaped > ";
            CDRExample *example = [CDRExample exampleWithText:stringToEscape andState:CDRExampleStateFailed];
            [reporter reportOnExample:example];

            [reporter runDidComplete];
            GDataXMLElement * testCase = [reporter.xmlRootElement elementsForName:@"testcase"][0];
            expect([[testCase attributeForName:@"name"] stringValue]).to(equal(stringToEscape));
        });

        it(@"should escape the failure reason", ^{

            NSString * exampleName = @"Failing spec 1";
            NSString * failureReason = @" Special ' characters \" should < be & escaped > ";
            NSString * fullExampleText = [NSString stringWithFormat:@"%@\n%@", exampleName, failureReason];
            CDRExample *example = [CDRExample exampleWithText:fullExampleText andState:CDRExampleStateFailed];
            example.failure = [CDRSpecFailure specFailureWithReason:failureReason];

            [reporter reportOnExample:example];

            [reporter runDidComplete];

            expect([[[reporter.xmlRootElement nodesForXPath:@"testcase/failure/text()" error:nil] firstObject] stringValue]).to(equal(failureReason));
        });
    });

    describe(@"each spec that causes an error", ^{
        it(@"should be handled the same as a failing spec", ^{
            CDRExample *example = [CDRExample exampleWithText:@"Failing spec\nFailure reason" andState:CDRExampleStateError];
            [reporter reportOnExample:example];

            [reporter runDidComplete];

            expect([[[reporter.xmlRootElement nodesForXPath:@"testcase/@classname" error:nil] firstObject] stringValue]).to(equal(@"Cedar"));
            expect([[[reporter.xmlRootElement nodesForXPath:@"testcase/@name" error:nil] firstObject] stringValue]).to(equal(@"Failing spec"));
            expect([[[reporter.xmlRootElement nodesForXPath:@"testcase/failure/@type" error:nil] firstObject] stringValue]).to(equal(@"Failure"));
            expect([[[reporter.xmlRootElement nodesForXPath:@"testcase/failure/text()" error:nil] firstObject] stringValue]).to(equal(@"Failure reason"));
        });
    });
});

SPEC_END
