unit TestPromiseAny;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.SyncObjs, System.Classes,
  Next.Core.Promises, Next.Core.Promises.Exceptions, Next.Core.Test.Assert;

type
  [TestFixture]
  TTestPromiseAny = class
  public
    [Test]
    /// <summary>
    /// Any with mixed results - resolves with the first successful value.
    /// </summary>
    procedure MixedResultsResolvesWithFirstSuccess;

    [Test]
    /// <summary>
    /// Any where all reject - rejects with EAggregateException containing all inner exceptions.
    /// </summary>
    procedure AllRejectAggregateException;

    [Test]
    /// <summary>
    /// Any where only the last one resolves - still resolves.
    /// </summary>
    procedure OnlyLastResolvesStillResolves;

    [Test]
    /// <summary>
    /// Any with a single resolving promise.
    /// </summary>
    procedure SingleResolvingPromise;

    [Test]
    /// <summary>
    /// Any with a single rejecting promise - rejects with EAggregateException containing one exception.
    /// </summary>
    procedure SingleRejectingPromise;

    [Test]
    /// <summary>
    /// Any with empty array - rejects with EArgumentException.
    /// </summary>
    procedure EmptyArrayRejects;

    [Test]
    /// <summary>
    /// Stress test: Any with many concurrent promises.
    /// </summary>
    procedure StressTestManyPromises;
  end;

implementation

{ TTestPromiseAny }

procedure TTestPromiseAny.MixedResultsResolvesWithFirstSuccess;
var
  LPromise: IPromise<Integer>;
  LSlowSignal: TEvent;
begin
  LSlowSignal := TEvent.Create;
  try
    LPromise := Promise.Any<Integer>([
      Promise.Reject<Integer>(ETestException.Create('error1')),
      Promise.Resolve<Integer>(function: Integer
        begin
          Result := 42;
        end),
      Promise.Resolve<Integer>(function: Integer
        begin
          LSlowSignal.WaitFor;
          Result := 99;
        end)
    ]);

    Assert.Resolves(LPromise);
    Assert.AreEqual(42, LPromise.Await);
    LSlowSignal.SetEvent;
  finally
    LSlowSignal.Free;
  end;
end;

procedure TTestPromiseAny.AllRejectAggregateException;
var
  LPromise: IPromise<Integer>;
begin
  LPromise := Promise.Any<Integer>([
    Promise.Reject<Integer>(ETestException.Create('error1')),
    Promise.Reject<Integer>(ETestException.Create('error2')),
    Promise.Reject<Integer>(ETestException.Create('error3'))
  ]);

  Assert.RejectsWith(LPromise, EAggregateException);

  // Verify all inner exceptions are present
  LPromise.InternalWait;
  var LAgg := LPromise.GetFailure.Reason as EAggregateException;
  Assert.AreEqual(3, Length(LAgg.Exceptions));
end;

procedure TTestPromiseAny.OnlyLastResolvesStillResolves;
var
  LPromise: IPromise<Integer>;
begin
  LPromise := Promise.Any<Integer>([
    Promise.Reject<Integer>(ETestException.Create('error1')),
    Promise.Reject<Integer>(ETestException.Create('error2')),
    Promise.Resolve<Integer>(function: Integer
      begin
        Sleep(50); // Give the rejections time to process
        Result := 42;
      end)
  ]);

  Assert.Resolves(LPromise);
  Assert.AreEqual(42, LPromise.Await);
end;

procedure TTestPromiseAny.SingleResolvingPromise;
var
  LPromise: IPromise<Integer>;
begin
  LPromise := Promise.Any<Integer>([
    Promise.Resolve<Integer>(function: Integer
      begin
        Result := 7;
      end)
  ]);

  Assert.Resolves(LPromise);
  Assert.AreEqual(7, LPromise.Await);
end;

procedure TTestPromiseAny.SingleRejectingPromise;
var
  LPromise: IPromise<Integer>;
begin
  LPromise := Promise.Any<Integer>([
    Promise.Reject<Integer>(ETestException.Create('only error'))
  ]);

  Assert.RejectsWith(LPromise, EAggregateException);

  LPromise.InternalWait;
  var LAgg := LPromise.GetFailure.Reason as EAggregateException;
  Assert.AreEqual(1, Length(LAgg.Exceptions));
  Assert.AreEqual('only error', LAgg.Exceptions[0].Message);
end;

procedure TTestPromiseAny.EmptyArrayRejects;
var
  LPromise: IPromise<Integer>;
begin
  LPromise := Promise.Any<Integer>([]);
  Assert.RejectsWith(LPromise, EArgumentException);
end;

procedure TTestPromiseAny.StressTestManyPromises;
var
  LPromises: TArray<IPromise<Integer>>;
  LPromise: IPromise<Integer>;
  i: Integer;
const
  COUNT = 50;
begin
  SetLength(LPromises, COUNT);
  // First 49 reject, last one resolves
  for i := 0 to COUNT - 2 do
  begin
    var LIndex := i;
    LPromises[i] := Promise.Reject<Integer>(
      ETestException.Create('error' + IntToStr(LIndex)));
  end;
  LPromises[COUNT - 1] := Promise.Resolve<Integer>(function: Integer
    begin
      Result := 999;
    end);

  LPromise := Promise.Any<Integer>(LPromises);
  Assert.Resolves(LPromise);
  Assert.AreEqual(999, LPromise.Await);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPromiseAny);

end.
