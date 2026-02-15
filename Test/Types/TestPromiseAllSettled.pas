unit TestPromiseAllSettled;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.SyncObjs, System.Classes,
  Next.Core.Promises, Next.Core.Promises.Exceptions, Next.Core.Test.Assert;

type
  [TestFixture]
  TTestPromiseAllSettled = class
  public
    [Test]
    /// <summary>
    /// All resolve - all results have psResolved.
    /// </summary>
    procedure AllResolve;

    [Test]
    /// <summary>
    /// All reject - all results have psRejected with correct exceptions.
    /// </summary>
    procedure AllReject;

    [Test]
    /// <summary>
    /// Mixed - verify correct status and values/errors per position.
    /// </summary>
    procedure MixedResults;

    [Test]
    /// <summary>
    /// Empty array - resolves immediately with empty array.
    /// </summary>
    procedure EmptyArrayResolvesEmpty;

    [Test]
    /// <summary>
    /// Order preserved - results match input order regardless of completion order.
    /// </summary>
    procedure OrderPreserved;

    [Test]
    /// <summary>
    /// Stress test with many promises.
    /// </summary>
    procedure StressTestManyPromises;
  end;

implementation

{ TTestPromiseAllSettled }

procedure TTestPromiseAllSettled.AllResolve;
var
  LPromise: IPromise<TArray<TPromiseSettledResult<Integer>>>;
  LResults: TArray<TPromiseSettledResult<Integer>>;
begin
  LPromise := Promise.AllSettled<Integer>([
    Promise.Resolve<Integer>(function: Integer begin Result := 1 end),
    Promise.Resolve<Integer>(function: Integer begin Result := 2 end),
    Promise.Resolve<Integer>(function: Integer begin Result := 3 end)
  ]);

  Assert.Resolves(LPromise);
  LResults := LPromise.Await;

  Assert.AreEqual(3, Length(LResults));
  Assert.AreEqual(Ord(TPromiseStatus.psResolved), Ord(LResults[0].Status));
  Assert.AreEqual(1, LResults[0].Value);
  Assert.IsNull(LResults[0].Error);

  Assert.AreEqual(Ord(TPromiseStatus.psResolved), Ord(LResults[1].Status));
  Assert.AreEqual(2, LResults[1].Value);

  Assert.AreEqual(Ord(TPromiseStatus.psResolved), Ord(LResults[2].Status));
  Assert.AreEqual(3, LResults[2].Value);
end;

procedure TTestPromiseAllSettled.AllReject;
var
  LPromise: IPromise<TArray<TPromiseSettledResult<Integer>>>;
  LResults: TArray<TPromiseSettledResult<Integer>>;
begin
  LPromise := Promise.AllSettled<Integer>([
    Promise.Reject<Integer>(ETestException.Create('error1')),
    Promise.Reject<Integer>(ETestException.Create('error2'))
  ]);

  Assert.Resolves(LPromise);
  LResults := LPromise.Await;

  Assert.AreEqual(2, Length(LResults));
  Assert.AreEqual(Ord(TPromiseStatus.psRejected), Ord(LResults[0].Status));
  Assert.IsNotNull(LResults[0].Error);
  Assert.AreEqual('error1', LResults[0].Error.Message);

  Assert.AreEqual(Ord(TPromiseStatus.psRejected), Ord(LResults[1].Status));
  Assert.IsNotNull(LResults[1].Error);
  Assert.AreEqual('error2', LResults[1].Error.Message);
end;

procedure TTestPromiseAllSettled.MixedResults;
var
  LPromise: IPromise<TArray<TPromiseSettledResult<Integer>>>;
  LResults: TArray<TPromiseSettledResult<Integer>>;
begin
  LPromise := Promise.AllSettled<Integer>([
    Promise.Resolve<Integer>(function: Integer begin Result := 42 end),
    Promise.Reject<Integer>(ETestException.Create('failed')),
    Promise.Resolve<Integer>(function: Integer begin Result := 99 end)
  ]);

  Assert.Resolves(LPromise);
  LResults := LPromise.Await;

  Assert.AreEqual(3, Length(LResults));

  // First: resolved
  Assert.AreEqual(Ord(TPromiseStatus.psResolved), Ord(LResults[0].Status));
  Assert.AreEqual(42, LResults[0].Value);
  Assert.IsNull(LResults[0].Error);

  // Second: rejected
  Assert.AreEqual(Ord(TPromiseStatus.psRejected), Ord(LResults[1].Status));
  Assert.IsNotNull(LResults[1].Error);
  Assert.AreEqual('failed', LResults[1].Error.Message);

  // Third: resolved
  Assert.AreEqual(Ord(TPromiseStatus.psResolved), Ord(LResults[2].Status));
  Assert.AreEqual(99, LResults[2].Value);
end;

procedure TTestPromiseAllSettled.EmptyArrayResolvesEmpty;
var
  LPromise: IPromise<TArray<TPromiseSettledResult<Integer>>>;
  LResults: TArray<TPromiseSettledResult<Integer>>;
begin
  LPromise := Promise.AllSettled<Integer>([]);
  Assert.Resolves(LPromise);
  LResults := LPromise.Await;
  Assert.AreEqual(0, Length(LResults));
end;

procedure TTestPromiseAllSettled.OrderPreserved;
var
  LSignals: array[0..2] of TEvent;
  LPromise: IPromise<TArray<TPromiseSettledResult<Integer>>>;
  LResults: TArray<TPromiseSettledResult<Integer>>;
  i: Integer;
begin
  for i := 0 to 2 do
    LSignals[i] := TEvent.Create;
  try
    LPromise := Promise.AllSettled<Integer>([
      Promise.Resolve<Integer>(function: Integer
        begin
          LSignals[0].WaitFor;
          Result := 100;
        end),
      Promise.Resolve<Integer>(function: Integer
        begin
          LSignals[1].WaitFor;
          Result := 200;
        end),
      Promise.Resolve<Integer>(function: Integer
        begin
          LSignals[2].WaitFor;
          Result := 300;
        end)
    ]);

    // Signal in reverse order to test that results match input order
    LSignals[2].SetEvent;
    Sleep(10);
    LSignals[1].SetEvent;
    Sleep(10);
    LSignals[0].SetEvent;

    Assert.Resolves(LPromise);
    LResults := LPromise.Await;

    Assert.AreEqual(3, Length(LResults));
    Assert.AreEqual(100, LResults[0].Value);
    Assert.AreEqual(200, LResults[1].Value);
    Assert.AreEqual(300, LResults[2].Value);
  finally
    for i := 0 to 2 do
      LSignals[i].Free;
  end;
end;

procedure TTestPromiseAllSettled.StressTestManyPromises;
var
  LPromises: TArray<IPromise<Integer>>;
  LPromise: IPromise<TArray<TPromiseSettledResult<Integer>>>;
  LResults: TArray<TPromiseSettledResult<Integer>>;
  i: Integer;
const
  COUNT = 50;
begin
  SetLength(LPromises, COUNT);
  for i := 0 to COUNT - 1 do
  begin
    var LIndex := i;
    if LIndex mod 2 = 0 then
      LPromises[i] := Promise.Resolve<Integer>(function: Integer
        begin Result := LIndex end)
    else
      LPromises[i] := Promise.Reject<Integer>(
        ETestException.Create('error' + IntToStr(LIndex)));
  end;

  LPromise := Promise.AllSettled<Integer>(LPromises);
  Assert.Resolves(LPromise);
  LResults := LPromise.Await;

  Assert.AreEqual(COUNT, Length(LResults));
  for i := 0 to COUNT - 1 do
  begin
    if i mod 2 = 0 then
    begin
      Assert.AreEqual(Ord(TPromiseStatus.psResolved), Ord(LResults[i].Status));
      Assert.AreEqual(i, LResults[i].Value);
    end
    else
    begin
      Assert.AreEqual(Ord(TPromiseStatus.psRejected), Ord(LResults[i].Status));
      Assert.IsNotNull(LResults[i].Error);
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPromiseAllSettled);

end.
